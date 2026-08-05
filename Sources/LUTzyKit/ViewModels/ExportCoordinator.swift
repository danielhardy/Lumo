import Foundation
import CoreImage
import AppKit

/// Owns everything about writing images to disk: the single export, the batch
/// run, and the naming rules both share.
///
/// Each operation is split in two — a `perform…` core that takes an explicit
/// destination, and a thin `…Dialog` wrapper that runs the panel and calls it.
/// The panels can't run headless, so that seam is what makes export testable
/// at all.
///
/// Status and error text goes out through `onStatus`/`onError` rather than
/// being written here: the status bar and the alert belong to `AppViewModel`,
/// and this type has no business deciding how a failure is presented.
@MainActor
final class ExportCoordinator: ObservableObject {

    @Published var format: ImageProcessor.ExportFormat = .jpeg
    @Published private(set) var isExporting: Bool = false
    /// Progress (0...1) during a multi-image "Export All" run.
    @Published private(set) var batchProgress: Double = 0

    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let processor = ImageProcessor.shared

    // MARK: - Types

    /// One image to export, reduced to the `Sendable` bits. Deliberately not
    /// `ImageCollection.Item`: that carries an `NSImage` thumbnail we don't
    /// want crossing an actor boundary.
    struct BatchItem: Sendable {
        let url: URL?
        let data: Data?
        let name: String

        init(url: URL?, data: Data?, name: String) {
            self.url = url
            self.data = data
            self.name = name
        }
    }

    struct BatchOutcome: Equatable {
        let exported: Int
        let failed: Int
        let total: Int
    }

    // MARK: - Naming

    // Pure and `nonisolated`: the batch loop needs them off the main actor.

    /// `‹photo›_‹LUT name›` — the shared stem for both export paths. Spaces in
    /// the LUT name become underscores so the result is shell-friendly.
    nonisolated static func exportBaseName(source: String, lut: CubeLUT?) -> String {
        let suffix = lut.map { "_" + $0.name.replacingOccurrences(of: " ", with: "_") } ?? ""
        return source + suffix
    }

    nonisolated static func defaultFileName(
        source: String,
        lut: CubeLUT?,
        format: ImageProcessor.ExportFormat
    ) -> String {
        exportBaseName(source: source, lut: lut) + "." + format.fileExtension
    }

    // MARK: - Single export

    /// Ask for a destination, then export. `suggestedBaseName` is the stem; the
    /// extension comes from the current format.
    func exportDialog(image: CIImage, suggestedBaseName: String) {
        let panel = NSSavePanel()
        panel.title = "Export"
        panel.nameFieldStringValue = suggestedBaseName + "." + format.fileExtension
        panel.allowedContentTypes = [format.utType]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        performExport(image, to: url)
    }

    /// Encode `image` to `url` off the main actor. Panel-free, so tests can
    /// drive it directly.
    func performExport(_ image: CIImage, to url: URL) {
        isExporting = true
        onStatus?("Exporting...")

        Task.detached { [processor, format] in
            do {
                try processor.export(image, to: url, format: format)
                await MainActor.run {
                    self.isExporting = false
                    self.onStatus?("Exported: \(url.lastPathComponent)")
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.onError?("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Batch export

    /// Ask for a folder, then apply `lut` at `intensity` to every item and
    /// write the results into it.
    func batchExportDialog(items: [BatchItem], lut: CubeLUT?, intensity: Double) {
        guard !items.isEmpty else {
            onStatus?("Import a set of images first (Export All works on the filmstrip)")
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.prompt = "Export Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        Task { await performBatchExport(items, lut: lut, intensity: intensity, to: folder) }
    }

    /// The batch core. Runs off the main actor with progress; an image that
    /// fails to load or encode is counted and skipped, never aborting the run.
    /// Returns the tally so callers (and tests) can assert on it.
    @discardableResult
    func performBatchExport(
        _ items: [BatchItem],
        lut: CubeLUT?,
        intensity: Double,
        to folder: URL
    ) async -> BatchOutcome {
        isExporting = true
        batchProgress = 0
        let total = items.count
        onStatus?("Exporting 0 of \(total)…")

        let fmt = format
        let outcome = await Task.detached { [processor] () -> BatchOutcome in
            var exported = 0
            var failed = 0

            for (index, item) in items.enumerated() {
                let source: CIImage?
                if let url = item.url {
                    source = try? processor.loadImage(from: url)
                } else if let data = item.data {
                    source = try? processor.loadImage(from: data, name: item.name)
                } else {
                    source = nil
                }

                if let source {
                    // Honor the intensity slider so Export All matches the preview.
                    let graded = lut?.apply(to: source, intensity: intensity) ?? source
                    let base = Self.exportBaseName(source: item.name, lut: lut)
                    let dest = uniqueExportURL(in: folder, base: base, ext: fmt.fileExtension)
                    do {
                        try processor.export(graded, to: dest, format: fmt)
                        exported += 1
                    } catch {
                        failed += 1
                    }
                } else {
                    failed += 1
                }

                let done = index + 1
                await MainActor.run {
                    self.batchProgress = Double(done) / Double(total)
                    self.onStatus?("Exporting \(done) of \(total)…")
                }
            }
            return BatchOutcome(exported: exported, failed: failed, total: total)
        }.value

        isExporting = false
        batchProgress = 0
        onStatus?(Self.summary(for: outcome, folder: folder))
        return outcome
    }

    /// The line shown when a batch finishes.
    nonisolated static func summary(for outcome: BatchOutcome, folder: URL) -> String {
        let destination = folder.lastPathComponent
        if outcome.failed == 0 {
            let plural = outcome.exported == 1 ? "" : "s"
            return "Exported \(outcome.exported) image\(plural) to \(destination)"
        }
        return "Exported \(outcome.exported) of \(outcome.total) (\(outcome.failed) failed) to \(destination)"
    }
}

// MARK: - Naming helpers

/// A non-colliding `base.ext` URL inside `folder`, appending " 2", " 3", …
/// when a file of that name already exists. Free function (not `@MainActor`)
/// so it can be called from the off-actor batch export task.
func uniqueExportURL(in folder: URL, base: String, ext: String) -> URL {
    let fm = FileManager.default
    var candidate = folder.appendingPathComponent("\(base).\(ext)")
    var n = 2
    while fm.fileExists(atPath: candidate.path) {
        candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
        n += 1
    }
    return candidate
}
