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

    @Published var isLoading: Bool = false
    @Published var isExporting: Bool = false
    @Published var statusMessage: String = "Open an image to get started"
    @Published var exportFormat: ImageProcessor.ExportFormat = .jpeg

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
            } catch {
                self.isLoading = false
                self.statusMessage = "Error: \(error.localizedDescription)"
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
                self.statusMessage = "\(sourceName)  \(Int(sourceSize.width))\u{00D7}\(Int(sourceSize.height))"
                self.isLoading = false

                updateOriginalPreview(ci)
                if selectedLUT != nil { applyLUT() } else { updatePreview(ci) }
            } catch {
                self.isLoading = false
                self.statusMessage = "Error: \(error.localizedDescription)"
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

    func importFolder() {
        let panel = NSOpenPanel()
        panel.title = "Import Image Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            collection.loadFromFolder(url)
            // Load the first image
            if let first = collection.items.first, let fileURL = first.url {
                openImage(url: fileURL)
            }
        }
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
    }

    func toggleSideBySide() {
        isSideBySide.toggle()
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
                        self.statusMessage = "Export failed: \(error.localizedDescription)"
                    }
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
                    self.statusMessage = "Derive failed: \(error.localizedDescription)"
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
                statusMessage = "Save failed: \(error.localizedDescription)"
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
