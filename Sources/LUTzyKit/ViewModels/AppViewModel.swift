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
    @Published var statusMessage: String = "Open an image to get started"

    /// Non-nil when a hard failure should be surfaced as a dismissible alert.
    /// Bound to an `.alert` in ContentView; cleared when the user dismisses it.
    @Published var errorMessage: String?

    @Published var isPhotosPickerPresented: Bool = false

    // MARK: - Owned state

    let library = LUTLibrary()
    let collection = ImageCollection()
    /// Writing images to disk — the single export, the batch run, and naming.
    let export = ExportCoordinator()
    /// The "Derive LUT from JPG" flow and its scratch-until-saved result.
    let derive = DeriveCoordinator()

    // Convenience passthroughs so views and the menu don't have to know which
    // collaborator owns a given piece of state.
    var isExporting: Bool { export.isExporting }
    var exportFormat: ImageProcessor.ExportFormat {
        get { export.format }
        set { export.format = newValue }
    }

    private let processor = ImageProcessor.shared
    private var loadTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var originalPreviewTask: Task<Void, Never>?
    private var intensityTask: Task<Void, Never>?
    private var cancellables: [AnyCancellable] = []

    // MARK: - Init

    init() {
        // Forward nested ObservableObject changes so SwiftUI views update.
        for child in [
            library.objectWillChange.eraseToAnyPublisher(),
            collection.objectWillChange.eraseToAnyPublisher(),
            export.objectWillChange.eraseToAnyPublisher(),
            derive.objectWillChange.eraseToAnyPublisher(),
        ] {
            cancellables.append(child.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            })
        }

        wireCoordinators()
        library.restoreFolder()

        // Restore a previously-chosen source folder and open its first image.
        // Both the LUT scan above and this one run asynchronously, so the
        // window paints immediately and fills in as the scans land.
        if collection.restoreSourceFolder() {
            isSourceBrowserPresented = true
            openFirstImageWhenScanned()
        }
    }

    /// Point the coordinators' status/error output at this view model, which
    /// owns the status bar and the alert. They report *what* happened; deciding
    /// how to show it stays here.
    private func wireCoordinators() {
        export.onStatus = { [weak self] in self?.statusMessage = $0 }
        export.onError = { [weak self] in self?.presentError($0) }

        derive.onStatus = { [weak self] in self?.statusMessage = $0 }
        derive.onError = { [weak self] in self?.presentError($0) }
        derive.onDerived = { [weak self] lut in
            // Preview the new look immediately, if there's something to see.
            guard let self, self.sourceImage != nil else { return }
            self.selectLUT(lut)
        }
        derive.libraryFolder = { [weak self] in self?.library.folderURL }
        derive.onSaved = { [weak self] _ in
            // Re-scan so the new entry appears in the sidebar.
            guard let self, let folder = self.library.folderURL else { return }
            self.library.scan(folder)
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

    /// The image the user is exporting: the graded result when a LUT is
    /// active, otherwise the untouched source.
    private var imageToExport: CIImage? {
        processedImage ?? sourceImage
    }

    func exportDialog() {
        guard let image = imageToExport else {
            statusMessage = "Open an image first"
            return
        }
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "image"
        export.exportDialog(
            image: image,
            suggestedBaseName: ExportCoordinator.exportBaseName(source: base, lut: selectedLUT)
        )
    }

    /// Apply the current LUT to every imported image and export them all to a
    /// chosen folder.
    func batchExportDialog() {
        // Snapshot only the Sendable bits — avoid carrying NSImage thumbnails
        // across the actor boundary.
        let items = collection.items.map {
            ExportCoordinator.BatchItem(url: $0.url, data: $0.imageData, name: $0.displayName)
        }
        export.batchExportDialog(items: items, lut: selectedLUT, intensity: lutIntensity)
    }

    // MARK: - Recipe extractor

    func presentRecipeExtractor() {
        derive.present()
    }

    func dismissRecipeExtractor() {
        derive.dismiss()
    }

    func deriveRecipe(rawURL: URL, jpgURL: URL) {
        derive.derive(rawURL: rawURL, jpgURL: jpgURL)
    }

    func saveDerivedLUT() {
        derive.saveDialog()
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
