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
///
/// **Step 6 cut both paths over to `RenderEngine`.** Neither one takes a `CIImage` any more: they
/// take the `ImageSource` and the `EditDocument` and ask the engine to encode at `.full`. That is
/// what makes an export honour develop and adjustments — before, the single path graded a
/// full-resolution neutral decode with only the LUT, and the batch path independently reproduced the
/// same omission with its own `loadImage` + `apply`. Two places to forget the same thing is exactly
/// why the fix is "hand the document to the one funnel" rather than "remember to grade twice".
///
/// It also removes the `[processor]` capture into `Task.detached` that §2 of the spec flags: the
/// non-`Sendable` singleton is gone from both loops, and the work now happens inside the actor that
/// owns the context.
@MainActor
final class ExportCoordinator: ObservableObject {

    @Published private(set) var isExporting: Bool = false
    /// Progress (0...1) during a multi-image "Export All" run.
    @Published private(set) var batchProgress: Double = 0
    /// Number of items that have reached a terminal state in the current batch.
    @Published private(set) var batchCompleted: Int = 0
    /// Total number of items in the current batch. Zero means that no batch is active.
    @Published private(set) var batchTotal: Int = 0
    /// The source currently in the expensive decode/render/commit section.
    @Published private(set) var batchCurrentItem: String?
    /// The format used by the most recently started export in this session.
    /// Both export dialogs use this to seed their accessory view.
    private(set) var lastUsedFormat: ExportFormat

    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?

    /// The renderer. `any RenderEngining` rather than the concrete actor for the same reason
    /// `AppViewModel` holds one: a test can then assert *what was asked to be encoded* — which
    /// document, at which scale, in which format — without a GPU or a file on disk.
    /// Production exports use a second RenderEngine actor/context/queue. A full-resolution encode
    /// is non-preemptible once Core Image enters it, so a batch cannot monopolize the display actor.
    /// The batch loop remains serial, retaining only one full-size result at a time.
    private let exportEngine: any RenderEngining
    private var batchTask: Task<BatchOutcome, Never>?
    /// This flag also makes the panel-free API cancellable: its caller may not own a task that the
    /// coordinator can cancel, but the UI still needs a reliable boundary before the next item.
    private var batchCancellationRequested = false

    /// The edit store is used for batch items that have not been opened in the current session.
    /// `lutResolver` is deliberately a value-returning main-actor seam: the store owns edit values,
    /// while the app's Look library owns the non-Codable LUT table.
    var lutResolver: ((LUTID?) -> CubeLUT?)?
    private let editStore: EditDocumentStore?

    init(
        engine: any RenderEngining = RenderEngine.shared,
        exportEngine: (any RenderEngining)? = nil,
        editStore: EditDocumentStore? = nil,
        lutResolver: ((LUTID?) -> CubeLUT?)? = nil
    ) {
        // Test renderers are deliberately shared so request assertions remain simple. The real
        // renderer gets isolated mutable Core Image state for export work.
        self.exportEngine = exportEngine ?? (engine is RenderEngine ? RenderEngine() : engine)
        self.editStore = editStore
        self.lutResolver = lutResolver
        self.lastUsedFormat = Self.defaultFormat
    }

    private static let defaultFormat: ExportFormat = .jpeg

    // MARK: - Types

    /// One image to export, reduced to the `Sendable` bits. Deliberately not
    /// `ImageCollection.Item`: that carries an `NSImage` thumbnail we don't
    /// want crossing an actor boundary.
    struct BatchItem: Sendable {
        let url: URL?
        let data: Data?
        let name: String
        /// Stable identity used to find the item's persisted edit record. It is optional so the
        /// original panel-free API remains source-compatible for callers that only have a URL/data
        /// pair.
        let assetID: PhotoAssetID?
        /// A source bookmark can outlive the folder scope that was active when the item was scanned.
        /// It is kept as data, never as an open security scope.
        let bookmarkData: Data?
        /// A live session snapshot wins over disk when the user edited this photo moments ago.
        /// `nil` means the coordinator should resolve the durable record.
        let document: EditDocument?
        /// The resolved table for `document.lut`. The document remains authoritative; a nil LUT is
        /// safe when the referenced Look is unavailable.
        let lut: CubeLUT?

        init(
            url: URL?, data: Data?, name: String,
            assetID: PhotoAssetID? = nil,
            bookmarkData: Data? = nil,
            document: EditDocument? = nil,
            lut: CubeLUT? = nil
        ) {
            self.url = url
            self.data = data
            self.name = name
            self.assetID = assetID ?? url.map(PhotoAssetID.file) ?? data.map(PhotoAssetID.data)
            self.bookmarkData = bookmarkData
            self.document = document
            self.lut = lut
        }
    }

    struct BatchOutcome: Equatable {
        let exported: Int
        let failed: Int
        let total: Int
        let cancelled: Bool

        init(exported: Int, failed: Int, total: Int, cancelled: Bool = false) {
            self.exported = exported
            self.failed = failed
            self.total = total
            self.cancelled = cancelled
        }

        var isCancelled: Bool { cancelled }
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
        format: ExportFormat
    ) -> String {
        exportBaseName(source: source, lut: lut) + "." + format.fileExtension
    }

    // MARK: - Single export

    /// Ask for a destination, then export. `suggestedBaseName` is the stem; the
    /// extension comes from the current format.
    func exportDialog(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        suggestedBaseName: String
    ) {
        let panel = NSSavePanel()
        let formatPicker = ExportFormatAccessoryView(selectedFormat: lastUsedFormat)
        panel.title = "Export"
        panel.nameFieldStringValue = suggestedBaseName + "." + formatPicker.selectedFormat.fileExtension
        panel.allowedContentTypes = [formatPicker.selectedFormat.utType]
        formatPicker.onSelectionChanged = { [weak panel] format in
            panel?.nameFieldStringValue = suggestedBaseName + "." + format.fileExtension
            panel?.allowedContentTypes = [format.utType]
        }
        panel.accessoryView = formatPicker

        guard panel.runModal() == .OK, let url = panel.url else { return }
        performExport(
            source: source, document: document, lut: lut, format: formatPicker.selectedFormat, to: url
        )
    }

    /// Encode `document` over `source` at full resolution and write it to `url`.
    /// Panel-free, so tests can drive it directly.
    ///
    /// The encode happens inside the engine; the *write* deliberately does not. File I/O is not the
    /// GPU's business, and keeping it out here means the actor never touches the sandbox or a
    /// half-written file (`RenderEngining.encode` returns `Data` for exactly this reason).
    func performExport(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        format: ExportFormat,
        to url: URL
    ) {
        performExport(
            source: source, document: document, lut: lut,
            options: ExportOptions(format: format, destination: .file(url)), to: url
        )
    }

    /// Validate and start one export from a complete, panel-independent policy.
    func performExport(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions,
        to url: URL
    ) {
        do {
            try options.validate()
        } catch {
            onError?("Export failed: \(error.localizedDescription)")
            return
        }
        lastUsedFormat = options.format
        isExporting = true
        onStatus?("Exporting...")

        Task { [weak self, exportEngine, options] in
            let hasDestinationScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasDestinationScope { url.stopAccessingSecurityScopedResource() }
            }
            var interval = LumoObservability.begin(.export, source: source, quality: .export)
            defer { interval.end() }
            do {
                try Task.checkCancellation()
                let data = try await exportEngine.render(RenderRequest(
                    source: source, document: document, lut: lut,
                    quality: .export,
                    output: .encoded(
                        format: options.format, quality: CGFloat(options.quality)
                    ),
                    space: options.colorSpace,
                    exportOptions: options
                )).data
                try Task.checkCancellation()
                try await Self.write(data, to: url)
                self?.isExporting = false
                self?.onStatus?("Exported: \(url.lastPathComponent)")
            } catch {
                self?.isExporting = false
                self?.onError?("Export failed: \(error.localizedDescription)")
            }
        }
    }

    /// Start a single export using the file destination embedded in options.
    func performExport(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions
    ) {
        guard case .file(let url)? = options.destination else {
            onError?("Export failed: a file destination is required.")
            return
        }
        performExport(source: source, document: document, lut: lut, options: options, to: url)
    }

    // MARK: - Batch export

    /// Ask for a folder, then render `document` over every item and write the
    /// results into it.
    func batchExportDialog(items: [BatchItem], document: EditDocument, lut: CubeLUT?) {
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
        panel.accessoryView = ExportFormatAccessoryView(selectedFormat: lastUsedFormat)
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let format = (panel.accessoryView as? ExportFormatAccessoryView)?.selectedFormat
            ?? lastUsedFormat
        // Record the choice as soon as the dialog completes, before the async batch starts.
        lastUsedFormat = format
        batchTask = Task { [weak self] in
            guard let self else {
                return BatchOutcome(exported: 0, failed: items.count, total: items.count)
            }
            return await self.performBatchExport(items, document: document, lut: lut, format: format, to: folder)
        }
    }

    /// Stop starting new items. If the renderer is at a cooperative cancellation point it also
    /// stops the current render; otherwise the current item finishes without being committed and
    /// the loop exits before another source is touched.
    func cancelBatchExport() {
        guard batchTotal > 0, isExporting else { return }
        batchCancellationRequested = true
        batchTask?.cancel()
        onStatus?("Cancelling export…")
    }

    /// The batch core. Renders each item through the engine with progress; an
    /// image that fails to decode or encode is counted and skipped, never
    /// aborting the run. Returns the tally so callers (and tests) can assert on it.
    ///
    /// The fallback `document`/`lut` arguments are retained for callers that intentionally want to
    /// apply one look to a set. A `BatchItem` with a live snapshot or a durable record always wins,
    /// which is what current/selected export uses.
    ///
    /// **Not memoized, deliberately.** The engine's developed-source memo only covers preview
    /// scales; a batch renders N *different* images at `.full`, so a memo would hold one
    /// full-resolution intermediate per item and never see a hit. See §6.
    @discardableResult
    func performBatchExport(
        _ items: [BatchItem],
        document: EditDocument,
        lut: CubeLUT?,
        format: ExportFormat,
        to folder: URL
    ) async -> BatchOutcome {
        await performBatchExport(
            items, document: document, lut: lut,
            options: ExportOptions(format: format, destination: .folder(folder)), to: folder
        )
    }

    /// Start a batch export using the folder destination embedded in options.
    @discardableResult
    func performBatchExport(
        _ items: [BatchItem],
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions
    ) async -> BatchOutcome {
        guard case .folder(let folder)? = options.destination else {
            onError?("Export failed: a folder destination is required.")
            return BatchOutcome(exported: 0, failed: items.count, total: items.count)
        }
        return await performBatchExport(
            items, document: document, lut: lut, options: options, to: folder
        )
    }

    /// Batch export using a complete, panel-independent policy.
    @discardableResult
    func performBatchExport(
        _ items: [BatchItem],
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions,
        to folder: URL
    ) async -> BatchOutcome {
        do {
            try options.validate()
        } catch {
            onError?("Export failed: \(error.localizedDescription)")
            return BatchOutcome(exported: 0, failed: items.count, total: items.count)
        }

        lastUsedFormat = options.format
        isExporting = true
        batchProgress = 0
        batchCompleted = 0
        batchTotal = items.count
        batchCurrentItem = nil
        batchCancellationRequested = false
        let total = items.count
        onStatus?("Exporting 0 of \(total)…")

        var exported = 0
        var failed = 0
        var cancelled = false

        // Reserve destinations in selection order before each render starts. The batch remains
        // serial to keep at most one full-resolution raster and encoded Data alive, while the
        // reservation set makes duplicate names deterministic and collision-free.
        var reservedPaths = Set<String>()

        let hasDestinationScope = folder.startAccessingSecurityScopedResource()
        defer {
            if hasDestinationScope { folder.stopAccessingSecurityScopedResource() }
        }

        for item in items {
            guard !Task.isCancelled, !batchCancellationRequested else {
                cancelled = true
                break
            }
            batchCurrentItem = item.name
            onStatus?("Exporting \(batchCompleted) of \(total)… \(item.name)")
            if let sourceAccess = Self.sourceAccess(for: item) {
                let source = sourceAccess.source
                let documentResolution = await resolvedDocument(for: item, fallback: document)
                guard !Task.isCancelled, !batchCancellationRequested else {
                    cancelled = true
                    break
                }
                let itemDocument = documentResolution.document
                let itemLUT: CubeLUT?
                if let itemLUTValue = item.lut {
                    itemLUT = itemLUTValue
                } else if documentResolution.isPerAsset {
                    // A missing Look is an intentional unresolved reference, not permission to
                    // leak the active photo's Look onto this asset.
                    itemLUT = lutResolver?(itemDocument.lut.lutID)
                } else {
                    itemLUT = lutResolver?(itemDocument.lut.lutID) ?? lut
                }
                let lookName = options.filenamePolicy == .sourceNameWithLook ? itemLUT?.name : nil
                let base = options.filenamePolicy.baseName(source: item.name, look: lookName)
                var dest = uniqueExportURL(
                    in: folder, base: base, ext: options.format.fileExtension
                )
                var counter = 2
                while reservedPaths.contains(dest.standardizedFileURL.path) {
                    dest = folder.appendingPathComponent(
                        "\(base) \(counter).\(options.format.fileExtension)"
                    )
                    counter += 1
                }
                reservedPaths.insert(dest.standardizedFileURL.path)
                do {
                    try Task.checkCancellation()
                    guard !batchCancellationRequested else { throw CancellationError() }
                    let hasSourceScope = sourceAccess.url?.startAccessingSecurityScopedResource() ?? false
                    defer {
                        if hasSourceScope { sourceAccess.url?.stopAccessingSecurityScopedResource() }
                    }
                    var interval = LumoObservability.begin(.export, source: source, quality: .export)
                    defer { interval.end() }
                    let data = try await exportEngine.render(RenderRequest(
                        source: source, document: itemDocument, lut: itemLUT,
                        quality: .export,
                        output: .encoded(
                            format: options.format, quality: CGFloat(options.quality)
                        ),
                        space: options.colorSpace,
                        exportOptions: options
                    )).data
                    try Task.checkCancellation()
                    guard !batchCancellationRequested else { throw CancellationError() }
                    try await Self.write(data, to: dest)
                    try Task.checkCancellation()
                    guard !batchCancellationRequested else { throw CancellationError() }
                    exported += 1
                } catch is CancellationError {
                    cancelled = true
                    break
                } catch {
                    failed += 1
                    onStatus?("Skipped \(item.name): \(error.localizedDescription)")
                }
            } else {
                failed += 1
                onStatus?("Skipped \(item.name): source unavailable")
            }

            let done = exported + failed
            batchCompleted = done
            batchProgress = Double(done) / Double(total)
            onStatus?("Exporting \(done) of \(total)…")
        }

        cancelled = cancelled || Task.isCancelled || batchCancellationRequested
        let outcome = BatchOutcome(
            exported: exported, failed: failed, total: total, cancelled: cancelled
        )
        isExporting = false
        batchProgress = 0
        batchCompleted = 0
        batchTotal = 0
        batchCurrentItem = nil
        onStatus?(Self.summary(for: outcome, folder: folder))
        batchTask = nil
        return outcome
    }

    /// Write off the main actor.
    ///
    /// Both loops are `@MainActor` now that the encode happens inside `RenderEngine` rather than in a
    /// detached task — but a full-resolution 16-bit TIFF is hundreds of megabytes, and handing that
    /// to the main thread would stutter the window for exactly as long as the disk takes. `Data` and
    /// `URL` are `Sendable`, so getting it off costs nothing.
    private static func write(_ data: Data, to url: URL) async throws {
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).partial"
        )
        var committed = false
        defer {
            if !committed { try? FileManager.default.removeItem(at: temporaryURL) }
        }

        try Task.checkCancellation()
        try await Task.detached(priority: .userInitiated) {
            try data.write(to: temporaryURL, options: .atomic)
        }.value
        try Task.checkCancellation()
        // moveItem does not replace an existing destination. That last boundary protects an
        // already-exported file even if another process creates the same name after reservation.
        try FileManager.default.moveItem(at: temporaryURL, to: url)
        committed = true
    }

    /// A resolved source plus the URL that may need a temporary security scope. The source itself
    /// always points at the original URL/data; it never points at a thumbnail or preview bitmap.
    private struct SourceAccess: Sendable {
        let source: ImageSource
        let url: URL?
    }

    /// How to reproduce a batch item, as an `ImageSource`.
    ///
    /// `nativeExtent` is `.zero` because a batch export never measures one: the extent exists so a
    /// *preview* can compute a downscale factor without decoding twice, and `RenderScale.full`
    /// returns 1.0 regardless. The pipeline reads the decoder's own size anyway, never this field
    /// (`RenderPipeline.developedSource`), so decoding every file up front just to fill it in would
    /// be pure cost.
    private static func sourceAccess(for item: BatchItem) -> SourceAccess? {
        if let url = item.url {
            let resolved = resolveScopedURL(url: url, bookmarkData: item.bookmarkData)
            return SourceAccess(
                source: ImageSource(url: resolved, nativeExtent: .zero),
                url: resolved
            )
        }
        if let data = item.data {
            return SourceAccess(source: ImageSource(data: data, nativeExtent: .zero), url: nil)
        }
        return nil
    }

    private static func resolveScopedURL(url: URL, bookmarkData: Data?) -> URL {
        guard let bookmarkData else { return url }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return url
        }
        return resolved
    }

    private func resolvedDocument(
        for item: BatchItem, fallback: EditDocument
    ) async -> (document: EditDocument, isPerAsset: Bool) {
        if let document = item.document { return (document, true) }
        guard let editStore, let assetID = item.assetID else { return (fallback, false) }
        let result = await editStore.load(for: EditSourceReference(assetID: assetID, url: item.url))
        return result.found ? (result.document, true) : (fallback, false)
    }

    /// The line shown when a batch finishes.
    nonisolated static func summary(for outcome: BatchOutcome, folder: URL) -> String {
        let destination = folder.lastPathComponent
        if outcome.cancelled {
            let processed = outcome.exported + outcome.failed
            let remaining = max(0, outcome.total - processed)
            return "Export cancelled after \(processed) of \(outcome.total) (\(outcome.exported) exported, \(outcome.failed) failed, \(remaining) not started) to \(destination)"
        }
        if outcome.failed == 0 {
            let plural = outcome.exported == 1 ? "" : "s"
            return "Exported \(outcome.exported) image\(plural) to \(destination)"
        }
        return "Exported \(outcome.exported) of \(outcome.total) (\(outcome.failed) failed) to \(destination)"
    }
}

// MARK: - Export format control

/// The format choice belongs to the export flow, alongside the destination, rather than in the
/// editor toolbar. Keeping this as an AppKit accessory also lets the Save panel update its filename
/// extension and content-type filter as the user changes the explicit export choice.
@MainActor
private final class ExportFormatAccessoryView: NSView {
    private let picker: NSSegmentedControl
    var onSelectionChanged: ((ExportFormat) -> Void)?

    init(selectedFormat: ExportFormat) {
        picker = NSSegmentedControl(
            labels: ExportFormat.allCases.map(\.rawValue),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(frame: .zero)

        let label = NSTextField(labelWithString: "Export format:")
        label.setContentHuggingPriority(.required, for: .horizontal)

        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.target = self
        picker.action = #selector(selectionChanged)
        picker.selectedSegment = ExportFormat.allCases.firstIndex(of: selectedFormat) ?? 0
        picker.setAccessibilityLabel("Export format")
        picker.setAccessibilityHelp("Choose TIFF, JPEG, or PNG for the exported image")

        let stack = NSStackView(views: [label, picker])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 300, height: 28)
    }

    var selectedFormat: ExportFormat {
        let index = picker.selectedSegment
        guard ExportFormat.allCases.indices.contains(index) else { return .jpeg }
        return ExportFormat.allCases[index]
    }

    @objc private func selectionChanged() {
        onSelectionChanged?(selectedFormat)
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
