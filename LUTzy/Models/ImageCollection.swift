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
        /// Relative directory from the source-folder root ("" for top level).
        /// Drives the grouped file browser; empty for Photos imports.
        var subfolder: String = ""
    }

    @Published var items: [Item] = []
    @Published var selectedIndex: Int = 0
    @Published var isActive: Bool = false
    /// The persistent source folder, if one is set (nil for Photos imports or
    /// one-off single-image opens).
    @Published var sourceFolderURL: URL?

    private static let bookmarkKey = "imageSourceFolderBookmark"
    private var thumbnailTask: Task<Void, Never>?

    var selectedItem: Item? {
        guard isActive, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    // MARK: - Source folder

    /// Set (and persist) a folder as the image source: saves a security-scoped
    /// bookmark, records the URL, and scans it. Mirrors `LUTLibrary`'s folder
    /// persistence so the source survives relaunches and the App Sandbox.
    func setSourceFolder(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            print("Failed to save source bookmark: \(error)")
        }
        sourceFolderURL = url
        loadFromFolder(url)
    }

    /// Restore a previously-chosen source folder on launch. Returns true if a
    /// folder was resolved and scanned.
    @discardableResult
    func restoreSourceFolder() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return false }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() else { return false }

        sourceFolderURL = url
        loadFromFolder(url)
        return true
    }

    /// Re-scan the current source folder (e.g. after files change on disk).
    func refresh() {
        guard let url = sourceFolderURL else { return }
        loadFromFolder(url)
    }

    /// Scan a folder recursively for supported images, recording each file's
    /// relative subfolder so the browser can group them. Items are ordered by
    /// subfolder, then natural filename order.
    func loadFromFolder(_ url: URL) {
        thumbnailTask?.cancel()
        items = []
        selectedIndex = 0

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // Resolve symlinks on both sides so the prefix math holds even when the
        // root is itself a symlink (e.g. /tmp → /private/tmp).
        let rootPath = url.resolvingSymlinksInPath().path
        var newItems: [Item] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard ImageProcessor.supportedExtensions.contains(ext) else { continue }
            let name = fileURL.deletingPathExtension().lastPathComponent
            let dir = fileURL.deletingLastPathComponent().resolvingSymlinksInPath().path
            let subfolder = dir.hasPrefix(rootPath)
                ? String(dir.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : ""
            newItems.append(Item(url: fileURL, displayName: name, imageData: nil, subfolder: subfolder))
        }

        newItems.sort { a, b in
            if a.subfolder != b.subfolder {
                return a.subfolder.localizedStandardCompare(b.subfolder) == .orderedAscending
            }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
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

    /// Clear the in-session collection (e.g. when opening a one-off single
    /// image). The persisted source-folder bookmark is left intact so it still
    /// restores on next launch; only the live browsing state is dropped.
    func clear() {
        thumbnailTask?.cancel()
        items = []
        selectedIndex = 0
        isActive = false
        sourceFolderURL = nil
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
