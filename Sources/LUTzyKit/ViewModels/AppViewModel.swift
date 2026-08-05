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
    private var loadTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var originalPreviewTask: Task<Void, Never>?
    private var intensityTask: Task<Void, Never>?
    private var deriveTask: Task<Void, Never>?
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
        // Both the LUT scan above and this one run asynchronously, so the
        // window paints immediately and fills in as the scans land.
        if collection.restoreSourceFolder() {
            isSourceBrowserPresented = true
            openFirstImageWhenScanned()
        }
    }

    /// Open the first image of the source folder once its scan completes.
    private func openFirstImageWhenScanned() {
        Task {
            await collection.scanCompletion()
            guard let first = collection.items.first, let fileURL = first.url else { return }
            openImage(url: fileURL)
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
        load(name: url.lastPathComponent, url: url, data: nil)
    }

    /// Decode an image **off the main actor**, then publish it and render the
    /// previews. RAW demosaicing is expensive enough (hundreds of ms) that
    /// doing it inline would freeze the window on every ←/→ step.
    private func load(name: String, url: URL?, data: Data?) {
        loadTask?.cancel()
        previewTask?.cancel()
        originalPreviewTask?.cancel()
        intensityTask?.cancel()

        isLoading = true
        statusMessage = "Loading \(name)..."

        loadTask = Task { [processor] in
            let decoded: Result<CIImage, Error> = await Task.detached {
                do {
                    if let url {
                        return .success(try processor.loadImage(from: url))
                    }
                    if let data {
                        return .success(try processor.loadImage(from: data, name: name))
                    }
                    return .failure(ImageError.cannotLoad(name))
                } catch {
                    return .failure(error)
                }
            }.value

            guard !Task.isCancelled else { return }

            switch decoded {
            case .failure(let error):
                self.isLoading = false
                self.presentError("Error: \(error.localizedDescription)")

            case .success(let ci):
                self.sourceImage = ci
                self.sourceURL = url
                self.sourceName = name
                self.sourceSize = ci.extent.size
                self.processedImage = nil
                self.statusMessage = "\(name)  \(Int(ci.extent.width))\u{00D7}\(Int(ci.extent.height))"
                self.isLoading = false

                self.scheduleOriginalPreview(ci)
                self.schedulePreview()
                self.refreshMetadata(url: url, data: data)
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
        load(name: name, url: nil, data: data)
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
        openFirstImageWhenScanned()
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
        schedulePreview()
    }

    /// Set the LUT strength (0...1) and re-render the preview. Safe to call on
    /// every slider tick: the re-render is debounced and the previous one is
    /// cancelled, so a full-travel drag costs a handful of renders, not one per
    /// pixel of travel.
    func setLUTIntensity(_ value: Double) {
        let clamped = max(0, min(1, value))
        guard clamped != lutIntensity else { return }
        lutIntensity = clamped

        intensityTask?.cancel()
        intensityTask = Task {
            try? await Task.sleep(for: .milliseconds(Self.intensityDebounceMs))
            guard !Task.isCancelled else { return }
            self.schedulePreview()
        }
    }

    // MARK: - Preview

    private let maxPreview = CGSize(width: 1600, height: 1200)
    private static let intensityDebounceMs = 60

    /// Rebuild `processedImage` for the current LUT + intensity and rasterize
    /// whichever image belongs on screen.
    ///
    /// Assembling the filter graph stays on the main actor — Core Image is lazy,
    /// so that part is nearly free. The **rasterization** is the expensive step
    /// and runs detached; the resulting `NSImage` is published back here. Any
    /// in-flight render is cancelled first, so rapid LUT/intensity changes drop
    /// stale work instead of queueing it.
    private func schedulePreview() {
        previewTask?.cancel()

        guard let source = sourceImage else {
            processedImage = nil
            previewNSImage = nil
            return
        }

        let graded: CIImage?
        if let lut = selectedLUT {
            graded = lut.apply(to: source, intensity: lutIntensity)
            if graded == nil { statusMessage = "LUT application failed" }
        } else {
            graded = nil
        }
        processedImage = graded

        let displayed = (isShowingOriginal ? nil : graded) ?? source

        previewTask = Task { [processor, maxPreview] in
            let rendered = await Task.detached {
                processor.renderPreview(displayed, maxSize: maxPreview)
            }.value
            guard !Task.isCancelled else { return }
            self.previewNSImage = rendered
            self.updateHistogram()
        }
    }

    /// Rasterize the untouched source for the side-by-side left panel. Only
    /// needs to run when the image itself changes.
    private func scheduleOriginalPreview(_ ciImage: CIImage) {
        originalPreviewTask?.cancel()
        originalPreviewTask = Task { [processor, maxPreview] in
            let rendered = await Task.detached {
                processor.renderPreview(ciImage, maxSize: maxPreview)
            }.value
            guard !Task.isCancelled else { return }
            self.originalPreviewNSImage = rendered
        }
    }

    /// Toggle between original and LUT preview (for Space-hold comparison).
    func showOriginal(_ show: Bool) {
        guard show != isShowingOriginal else { return }
        isShowingOriginal = show
        schedulePreview()
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

    /// Close the sheet. A derive still in flight is cancelled — it can run for
    /// tens of seconds and hold several hundred MB, so leaving it running after
    /// the user has walked away is never what they want.
    ///
    /// A *finished* result is kept: the user may re-open the sheet to inspect
    /// the report or save the LUT. The scratch file is cleaned up when a new
    /// derive starts (see `deriveRecipe`).
    func dismissRecipeExtractor() {
        isRecipeSheetPresented = false
        if isDeriving {
            deriveTask?.cancel()
            deriveTask = nil
            isDeriving = false
            deriveProgress = 0
            deriveStage = ""
            statusMessage = "Derive cancelled"
        }
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

        deriveTask = Task.detached {
            do {
                let result = try RecipeExtractor.derive(
                    rawURL: rawURL,
                    jpgURL: jpgURL,
                    progress: { progress, stage in
                        Task { @MainActor in
                            self.deriveProgress = progress
                            self.deriveStage = stage
                        }
                    },
                    isCancelled: { Task.isCancelled }
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
            } catch is CancellationError {
                // Nothing to undo: the scratch .cube is only written after
                // `derive` returns, and `dismissRecipeExtractor` (the only
                // thing that cancels) has already reset the UI state.
                return
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
