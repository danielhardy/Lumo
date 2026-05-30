import Foundation
import AppKit

/// Manages a collection of imported images with async thumbnail generation.
@MainActor
final class ImageCollection: ObservableObject {

    struct Item: Identifiable {
        let id = UUID()
        let url: URL?               // nil for Photos-imported items
        let displayName: String
        var thumbnail: NSImage?
        let imageData: Data?         // for PhotosPicker items without a URL
    }

    @Published var items: [Item] = []
    @Published var selectedIndex: Int = 0
    @Published var isActive: Bool = false

    /// All image extensions LUTzy can open.
    private static let supportedExtensions: Set<String> = [
        "dng", "cr2", "cr3", "nef", "arw", "orf", "raf", "rw2", "pef", "srw", "x3f", "raw",
        "jpg", "jpeg", "png", "tiff", "tif", "bmp", "heic",
    ]

    private var thumbnailTask: Task<Void, Never>?

    var selectedItem: Item? {
        guard isActive, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    // MARK: - Folder import

    func loadFromFolder(_ url: URL) {
        thumbnailTask?.cancel()
        items = []
        selectedIndex = 0

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        var newItems: [Item] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { continue }
            let name = fileURL.deletingPathExtension().lastPathComponent
            newItems.append(Item(url: fileURL, displayName: name, imageData: nil))
        }

        newItems.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        items = newItems
        isActive = items.count > 1
        generateThumbnails()
    }

    // MARK: - Data import (from Photos picker)

    func addFromData(_ dataItems: [(name: String, data: Data)]) {
        thumbnailTask?.cancel()
        items = []
        selectedIndex = 0
        let processor = ImageProcessor.shared

        var newItems: [Item] = []
        for item in dataItems {
            let thumb = processor.generateThumbnail(from: item.data)
            newItems.append(Item(url: nil, displayName: item.name, thumbnail: thumb, imageData: item.data))
        }
        self.items = newItems
        self.isActive = items.count > 1
    }

    // MARK: - Navigation

    func selectNext() {
        guard isActive, selectedIndex < items.count - 1 else { return }
        selectedIndex += 1
    }

    func selectPrevious() {
        guard isActive, selectedIndex > 0 else { return }
        selectedIndex -= 1
    }

    func clear() {
        thumbnailTask?.cancel()
        items = []
        selectedIndex = 0
        isActive = false
    }

    // MARK: - Thumbnail generation

    private func generateThumbnails() {
        let processor = ImageProcessor.shared
        thumbnailTask = Task {
            for i in items.indices {
                guard !Task.isCancelled else { return }
                guard items[i].thumbnail == nil, let url = items[i].url else { continue }

                let thumb = await Task.detached {
                    processor.generateThumbnail(from: url)
                }.value

                guard !Task.isCancelled, items.indices.contains(i) else { return }
                items[i].thumbnail = thumb
            }
        }
    }
}
