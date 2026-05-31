import Foundation
import CoreImage
import AppKit
import Combine
import UniformTypeIdentifiers

/// Central state for the LUTzy app.
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Published state

    @Published var sourceImage: CIImage?
    @Published var sourceName: String = ""
    @Published var sourceSize: CGSize = .zero
    @Published var sourceURL: URL?

    @Published var selectedLUT: CubeLUT?
    @Published var processedImage: CIImage?

    /// LUT strength, 0...1 (1 = full LUT, 0 = original). Persists across LUT
    /// changes so a chosen strength can be auditioned against different looks.
    @Published var lutIntensity: Double = 1.0

    @Published var previewNSImage: NSImage?
    @Published var originalPreviewNSImage: NSImage?
    @Published var isShowingOriginal: Bool = false
    @Published var isSideBySide: Bool = true

    /// Info inspector (EXIF + histogram) visibility. Computing the histogram is
    /// gated on this so we don't tally pixels for a panel nobody's looking at.
    @Published var isInspectorPresented: Bool = false {
        didSet { if isInspectorPresented { updateHistogram() } }
    }
    /// Source-folder file browser panel visibility.
    @Published var isSourceBrowserPresented: Bool = false
    /// EXIF/TIFF/GPS metadata of the loaded image, read at load time.
    @Published var metadata: ImageMetadata = ImageMetadata()
    /// Histogram of the currently displayed image (graded result, or original
    /// while comparing). `nil` until computed / when no image is loaded.
    @Published var histogram: HistogramData?
    private var histogramTask: Task<Void, Never>?

    @Published var isLoading: Bool = false
    @Published var isExporting: Bool = false
    /// Progress (0...1) during a multi-image "Export All" run.
    @Published var batchProgress: Double = 0
    @Published var statusMessage: String = "Open an image to get started"
    @Published var exportFormat: ImageProcessor.ExportFormat = .jpeg

    /// Non-nil when a hard failure should be surfaced as a dismissible alert.
    /// Bound to an `.alert` in ContentView; cleared when the user dismisses it.
    @Published var errorMessage: String?

    @Published var isPhotosPickerPresented: Bool = false

    // MARK: - Recipe extractor state (scratch — not saved until the user clicks Save)

    @Published var isRecipeSheetPresented: Bool = false
    @Published var isDeriving: Bool = false
    @Published var deriveProgress: Double = 0
    @Published var deriveStage: String = ""
    @Published var derivedLUT: CubeLUT?
    @Published var derivedReport: RecipeReport?
    /// Path to the in-memory derived .cube serialized to a temp file so it can
    /// be saved with a single FileManager.copy. Cleared on dismiss / new derive.
    private var derivedScratchURL: URL?

    let library = LUTLibrary()
    let collection = ImageCollection()

    private let processor = ImageProcessor.shared
    private var previewTask: Task<Void, Never>?
    private var collectionCancellable: AnyCancellable?
    private var libraryCancellable: AnyCancellable?

    // MARK: - Init

    init() {
        // Forward nested ObservableObject changes so SwiftUI views update
        libraryCancellable = library.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
        collectionCancellable = collection.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
        library.restoreFolder()

        // Restore a previously-chosen source folder and open its first image.
        if collection.restoreSourceFolder() {
            isSourceBrowserPresented = true
            if let first = collection.items.first, let fileURL = first.url {
                openImage(url: fileURL)
            }
        }
    }

    // MARK: - Error presentation

    /// Surface a user-facing error both as a dismissible alert and in the
    /// status bar. Used for hard failures (load / export / derive / save);
    /// transient preview hiccups stay status-bar-only to avoid alert spam.
    private func presentError(_ message: String) {
        statusMessage = message
        errorMessage = message
    }

    // MARK: - Image loading

    func openImage(url: URL) {
        isLoading = true
        statusMessage = "Loading \(url.lastPathComponent)..."

        Task {
            do {
                let ci = try processor.loadImage(from: url)
                self.sourceImage = ci
                self.sourceURL = url
                self.sourceName = url.lastPathComponent
                self.sourceSize = ci.extent.size
                self.processedImage = nil
                self.statusMessage = "\(sourceName)  \(Int(sourceSize.width))×\(Int(sourceSize.height))"
                self.isLoading = false

                // Always render the original preview
                updateOriginalPreview(ci)

                // Apply current LUT if one is selected
                if selectedLUT != nil {
                    applyLUT()
                } else {
                    updatePreview(ci)
                }

                refreshMetadata(url: url, data: nil)
                updateHistogram()
            } catch {
                self.isLoading = false
                self.presentError("Error: \(error.localizedDescription)")
            }
        }
    }

    func openImageDialog() {
        let panel = NSOpenPanel()
        panel.title = "Open Image"
        panel.allowedContentTypes = ImageProcessor.supportedTypes
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            collection.clear()
            openImage(url: url)
        }
    }

    // MARK: - Photo import

    func openImage(data: Data, name: String) {
        isLoading = true
        statusMessage = "Loading \(name)..."

        Task {
            do {
                guard let ci = CIImage(data: data) else {
                    throw ImageError.cannotLoad(name)
                }
                self.sourceImage = ci
                self.sourceURL = nil
                self.sourceName = name
                self.sourceSize = ci.extent.size
                self.processedImage = nil
                self.statusMessage = "\(sourceName)  \(Int(sourceSize.width))\u{00D7}\(Int(sourceSize.height))"
                self.isLoading = false

                updateOriginalPreview(ci)
                if selectedLUT != nil { applyLUT() } else { updatePreview(ci) }

                refreshMetadata(url: nil, data: data)
                updateHistogram()
            } catch {
                self.isLoading = false
                self.presentError("Error: \(error.localizedDescription)")
            }
        }
    }

    func importFromPhotos() {
        isPhotosPickerPresented = true
    }

    func importPhotosData(_ items: [(name: String, data: Data)]) {
        collection.addFromData(items)
        if let first = items.first {
            openImage(data: first.data, name: first.name)
        }
    }

    /// Choose a folder to use as the persistent image source, scan it (incl.
    /// subfolders), reveal the file browser, and open the first image.
    func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Source Folder"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            openSourceFolder(url: url)
        }
    }

    /// Adopt `url` as the source folder (persisted), reveal the browser, and
    /// open its first image. Shared by the menu/toolbar action and folder drops.
    func openSourceFolder(url: URL) {
        collection.setSourceFolder(url)
        isSourceBrowserPresented = true
        if let first = collection.items.first, let fileURL = first.url {
            openImage(url: fileURL)
        }
    }

    func toggleSourceBrowser() {
        isSourceBrowserPresented.toggle()
    }

    /// Re-scan the current source folder for added/removed files.
    func refreshSource() {
        collection.refresh()
    }

    func selectCollectionImage(at index: Int) {
        guard collection.items.indices.contains(index) else { return }
        collection.selectedIndex = index
        let item = collection.items[index]

        if let url = item.url {
            openImage(url: url)
        } else if let data = item.imageData {
            openImage(data: data, name: item.displayName)
        }
    }

    func selectPreviousImage() {
        guard collection.isActive else { return }
        let prev = collection.selectedIndex
        collection.selectPrevious()
        if collection.selectedIndex != prev {
            selectCollectionImage(at: collection.selectedIndex)
        }
    }

    func selectNextImage() {
        guard collection.isActive else { return }
        let prev = collection.selectedIndex
        collection.selectNext()
        if collection.selectedIndex != prev {
            selectCollectionImage(at: collection.selectedIndex)
        }
    }

    // MARK: - LUT selection

    func selectLUT(_ lut: CubeLUT?) {
        selectedLUT = lut
        applyLUT()
    }

    func selectPreviousLUT() {
        guard let current = selectedLUT,
              let idx = library.allLUTs.firstIndex(of: current),
              idx > 0 else { return }
        selectLUT(library.allLUTs[idx - 1])
    }

    func selectNextLUT() {
        guard let current = selectedLUT else {
            if let first = library.allLUTs.first { selectLUT(first) }
            return
        }
        guard let idx = library.allLUTs.firstIndex(of: current),
              idx < library.allLUTs.count - 1 else { return }
        selectLUT(library.allLUTs[idx + 1])
    }

    // MARK: - LUT application

    private func applyLUT() {
        guard let source = sourceImage else { return }

        // Cancel any in-flight preview
        previewTask?.cancel()

        guard let lut = selectedLUT else {
            processedImage = nil
            updatePreview(source)
            updateHistogram()
            return
        }

        previewTask = Task {
            guard let result = lut.apply(to: source, intensity: lutIntensity) else {
                self.statusMessage = "LUT application failed"
                return
            }
            guard !Task.isCancelled else { return }
            self.processedImage = result
            self.updatePreview(result)
            self.updateHistogram()
        }
    }

    /// Set the LUT strength (0...1) and re-render the preview. Cheap to call
    /// repeatedly while dragging — `applyLUT` cancels any in-flight render.
    func setLUTIntensity(_ value: Double) {
        let clamped = max(0, min(1, value))
        guard clamped != lutIntensity else { return }
        lutIntensity = clamped
        applyLUT()
    }

    // MARK: - Preview

    private let maxPreview = CGSize(width: 1600, height: 1200)

    private func updatePreview(_ ciImage: CIImage) {
        previewNSImage = processor.renderPreview(ciImage, maxSize: maxPreview)
    }

    private func updateOriginalPreview(_ ciImage: CIImage) {
        originalPreviewNSImage = processor.renderPreview(ciImage, maxSize: maxPreview)
    }

    /// Toggle between original and LUT preview (for Space-hold comparison).
    func showOriginal(_ show: Bool) {
        isShowingOriginal = show
        if let source = sourceImage {
            if show || processedImage == nil {
                updatePreview(source)
            } else if let processed = processedImage {
                updatePreview(processed)
            }
        }
        updateHistogram()
    }

    func toggleSideBySide() {
        isSideBySide.toggle()
    }

    // MARK: - Info inspector (EXIF + histogram)

    func toggleInspector() {
        isInspectorPresented.toggle()
    }

    /// The image the histogram should describe: the original while comparing
    /// (Space held), the graded result when a LUT is active, otherwise source.
    private var histogramSourceImage: CIImage? {
        if isShowingOriginal { return sourceImage }
        if selectedLUT != nil, let processed = processedImage { return processed }
        return sourceImage
    }

    /// Recompute the histogram for the currently displayed image. No-op while
    /// the inspector is closed. Cheap (downscaled tally) but run off-actor and
    /// cancellable so dragging the intensity slider stays smooth.
    private func updateHistogram() {
        guard isInspectorPresented else { return }
        guard let image = histogramSourceImage else {
            histogram = nil
            return
        }
        histogramTask?.cancel()
        histogramTask = Task.detached { [processor] in
            let result = processor.histogram(of: image)
            if Task.isCancelled { return }
            await MainActor.run { self.histogram = result }
        }
    }

    /// Read EXIF/TIFF/GPS metadata off the main actor and publish it.
    private func refreshMetadata(url: URL?, data: Data?) {
        Task.detached {
            let meta: ImageMetadata
            if let url {
                meta = ImageMetadata.read(from: url)
            } else if let data {
                meta = ImageMetadata.read(from: data)
            } else {
                meta = ImageMetadata()
            }
            await MainActor.run { self.metadata = meta }
        }
    }

    // MARK: - Export

    func exportDialog() {
        guard sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }

        let imageToExport = processedImage ?? sourceImage!
        let lutSuffix = selectedLUT.map { "_" + $0.name.replacingOccurrences(of: " ", with: "_") } ?? ""
        let baseName = sourceURL?.deletingPathExtension().lastPathComponent ?? "image"
        let defaultName = baseName + lutSuffix + "." + exportFormat.fileExtension

        let panel = NSSavePanel()
        panel.title = "Export"
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [exportFormat.utType]

        if panel.runModal() == .OK, let url = panel.url {
            isExporting = true
            statusMessage = "Exporting..."

            Task.detached { [processor, exportFormat] in
                do {
                    try processor.export(imageToExport, to: url, format: exportFormat)
                    await MainActor.run {
                        self.isExporting = false
                        self.statusMessage = "Exported: \(url.lastPathComponent)"
                    }
                } catch {
                    await MainActor.run {
                        self.isExporting = false
                        self.presentError("Export failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Apply the current LUT to every imported image and export them all to a
    /// chosen folder. Runs off the main actor with progress; images that fail
    /// to load or encode are skipped and counted, never aborting the batch.
    func batchExportDialog() {
        // Snapshot only the Sendable bits we need — avoid carrying NSImage
        // thumbnails across the actor boundary.
        let work = collection.items.map {
            (url: $0.url, data: $0.imageData, name: $0.displayName)
        }
        guard !work.isEmpty else {
            statusMessage = "Import a set of images first (Export All works on the filmstrip)"
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

        isExporting = true
        batchProgress = 0
        let total = work.count
        statusMessage = "Exporting 0 of \(total)…"

        let lut = selectedLUT
        let fmt = exportFormat
        let intensity = lutIntensity

        Task.detached { [processor] in
            var exported = 0
            var failed = 0

            for (index, item) in work.enumerated() {
                let source: CIImage?
                if let url = item.url {
                    source = try? processor.loadImage(from: url)
                } else if let data = item.data {
                    source = CIImage(data: data)
                } else {
                    source = nil
                }

                if let source {
                    // Honor the intensity slider so Export All matches the preview.
                    let graded = lut?.apply(to: source, intensity: intensity) ?? source
                    let suffix = lut.map { "_" + $0.name.replacingOccurrences(of: " ", with: "_") } ?? ""
                    let dest = uniqueExportURL(in: folder, base: item.name + suffix, ext: fmt.fileExtension)
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
                    self.statusMessage = "Exporting \(done) of \(total)…"
                }
            }

            let okCount = exported
            let failCount = failed
            await MainActor.run {
                self.isExporting = false
                self.batchProgress = 0
                let dest = folder.lastPathComponent
                if failCount == 0 {
                    self.statusMessage = "Exported \(okCount) image\(okCount == 1 ? "" : "s") to \(dest)"
                } else {
                    self.statusMessage = "Exported \(okCount) of \(total) (\(failCount) failed) to \(dest)"
                }
            }
        }
    }

    // MARK: - Recipe extractor

    func presentRecipeExtractor() {
        isRecipeSheetPresented = true
    }

    func dismissRecipeExtractor() {
        isRecipeSheetPresented = false
        // Keep the scratch state — user might re-open the sheet to inspect.
        // It's only cleared when a new derive starts or on app exit.
    }

    /// Derive a LUT from a (RAW, JPG) pair. Result lives in `derivedLUT` and
    /// `derivedReport` until the user explicitly Saves it.
    func deriveRecipe(rawURL: URL, jpgURL: URL) {
        guard !isDeriving else { return }
        isDeriving = true
        deriveProgress = 0
        deriveStage = "Starting…"
        statusMessage = "Deriving recipe…"
        derivedLUT = nil
        derivedReport = nil

        // Clean up any previous scratch file
        if let prev = derivedScratchURL {
            try? FileManager.default.removeItem(at: prev)
            derivedScratchURL = nil
        }

        Task.detached {
            do {
                let result = try RecipeExtractor.derive(
                    rawURL: rawURL,
                    jpgURL: jpgURL,
                    progress: { progress, stage in
                        Task { @MainActor in
                            self.deriveProgress = progress
                            self.deriveStage = stage
                        }
                    }
                )

                // Serialize the derived cube to a temp .cube so saving later is
                // a one-line FileManager.copy. The CubeLUT itself is already
                // built in-memory via the new init(cube:size:name:...) — the
                // scratch file is just a save-time convenience.
                let cubeName = jpgURL.deletingPathExtension().lastPathComponent + "_recipe_\(result.size)_Rec709"
                let scratchURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(cubeName).cube")
                try CubeLUT.write(
                    cube: result.cube,
                    size: result.size,
                    title: cubeName,
                    to: scratchURL
                )

                let lut = CubeLUT(
                    cube: result.cube,
                    size: result.size,
                    name: cubeName,
                    category: "Derived",
                    sourceURL: scratchURL
                )

                await MainActor.run {
                    self.derivedLUT = lut
                    self.derivedReport = result.report
                    self.derivedScratchURL = scratchURL
                    self.isDeriving = false
                    self.deriveProgress = 1.0
                    self.deriveStage = "Done"
                    self.statusMessage = "Recipe derived (\(result.report.sampleCount) samples)"
                    // Apply to the current source for live preview
                    if self.sourceImage != nil {
                        self.selectLUT(lut)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isDeriving = false
                    self.deriveProgress = 0
                    self.deriveStage = ""
                    self.presentError("Derive failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Save the current scratch LUT to disk. Defaults to the configured LUT
    /// folder so the LUTLibrary picks it up on next scan.
    func saveDerivedLUT() {
        guard let lut = derivedLUT, let scratch = derivedScratchURL else {
            statusMessage = "No derived LUT to save"
            return
        }
        let panel = NSSavePanel()
        panel.title = "Save Derived LUT"
        if let cubeType = UTType(filenameExtension: "cube") {
            panel.allowedContentTypes = [cubeType]
        }
        panel.nameFieldStringValue = lut.name + ".cube"
        if let folder = library.folderURL {
            panel.directoryURL = folder
        }

        if panel.runModal() == .OK, let dest = panel.url {
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: scratch, to: dest)
                statusMessage = "Saved: \(dest.lastPathComponent)"
                // Re-scan the LUT folder so the new entry appears in the sidebar
                if let folder = library.folderURL {
                    library.scan(folder)
                }
            } catch {
                presentError("Save failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - LUT folder

    func chooseLUTFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select LUT Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            library.setFolder(url)
        }
    }
}

// MARK: - Batch export helpers

/// A non-colliding `base.ext` URL inside `folder`, appending " 2", " 3", …
/// when a file of that name already exists. Free function (not `@MainActor`)
/// so it can be called from the off-actor batch export task.
private func uniqueExportURL(in folder: URL, base: String, ext: String) -> URL {
    let fm = FileManager.default
    var candidate = folder.appendingPathComponent("\(base).\(ext)")
    var n = 2
    while fm.fileExists(atPath: candidate.path) {
        candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
        n += 1
    }
    return candidate
}
