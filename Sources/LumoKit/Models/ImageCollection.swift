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
    private var scanTask: Task<Void, Never>?
    private let scheduler: ImageWorkScheduler
    private var thumbnailJobIDs: Set<ImageWorkScheduler.JobID> = []
    private var thumbnailGeneration: UInt64 = 0
    /// Folder whose security scope we hold open, released when we move on.
    private var scopedURL: URL?

    init(scheduler: ImageWorkScheduler = ImageWorkScheduler()) {
        self.scheduler = scheduler
    }

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    var selectedItem: Item? {
        guard isActive, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    // MARK: - Source folder

    /// Set (and persist) a folder as the image source: saves a security-scoped
    /// bookmark, records the URL, and scans it. Mirrors `LUTLibrary`'s folder
    /// persistence so the source survives relaunches and the App Sandbox.
    func setSourceFolder(_ url: URL) {
        saveBookmark(for: url)
        sourceFolderURL = url
        loadFromFolder(url)
    }

    /// Restore a previously-chosen source folder on launch. Returns true if a
    /// folder was resolved; the scan itself runs asynchronously.
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

        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = url

        // A stale bookmark resolves this once but won't next launch; mint a
        // fresh one now that access is held.
        if isStale { saveBookmark(for: url) }

        sourceFolderURL = url
        loadFromFolder(url)
        return true
    }

    private func saveBookmark(for url: URL) {
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
    }

    /// Re-scan the current source folder (e.g. after files change on disk).
    func refresh() {
        guard let url = sourceFolderURL else { return }
        loadFromFolder(url)
    }

    /// Wait for the in-flight folder scan to finish, so callers that need to
    /// act on `items` (open the first image, say) can do so without racing it.
    func scanCompletion() async {
        await scanTask?.value
    }

    /// Scan a folder recursively for supported images, recording each file's
    /// relative subfolder so the browser can group them. Items are ordered by
    /// subfolder, then natural filename order.
    ///
    /// The enumeration runs off the main actor — a deep folder on a slow or
    /// network volume would otherwise stall the window, and this runs during
    /// app launch when a source folder is restored.
    func loadFromFolder(_ url: URL) {
        cancelThumbnailWork()
        scanTask?.cancel()
        items = []
        selectedIndex = 0
        isActive = false

        scanTask = Task {
            let scanned = await Task.detached { Self.scanFolder(url) }.value
            guard !Task.isCancelled else { return }
            self.items = scanned
            self.isActive = !scanned.isEmpty
            self.generateThumbnails()
        }
    }

    /// The blocking half of `loadFromFolder`. `nonisolated` so it can run on a
    /// background executor — it touches no instance state.
    private nonisolated static func scanFolder(_ url: URL) -> [Item] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Resolve symlinks on both sides so the prefix math holds even when the
        // root is itself a symlink (e.g. /tmp → /private/tmp).
        let rootPath = url.resolvingSymlinksInPath().path
        var newItems: [Item] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { return [] }
            let ext = fileURL.pathExtension.lowercased()
            guard ImageDecoder.supportedExtensions.contains(ext) else { continue }
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
        return newItems
    }

    // MARK: - Data import (from Photos picker)

    /// Adopt a set of Photos-picker payloads as the collection.
    ///
    /// **The second thumbnail site.** `generateThumbnails` below is the obvious one; this one builds
    /// its thumbnails inline and is easy to miss when the thumbnail path moves — which is why
    /// `docs/PHASE2_SPEC.md` §6 names both explicitly. Step 7 pointed both at `Thumbnails`.
    func addFromData(_ dataItems: [(name: String, data: Data)]) {
        cancelThumbnailWork()
        items = []
        selectedIndex = 0

        var newItems: [Item] = []
        for item in dataItems {
            newItems.append(Item(url: nil, displayName: item.name, thumbnail: nil, imageData: item.data))
        }
        self.items = newItems
        self.isActive = !items.isEmpty
        enqueueThumbnails()
    }

    // MARK: - Navigation

    func selectNext() {
        guard isActive, selectedIndex < items.count - 1 else { return }
        selectedIndex += 1
        reprioritizeThumbnails()
    }

    func selectPrevious() {
        guard isActive, selectedIndex > 0 else { return }
        selectedIndex -= 1
        reprioritizeThumbnails()
    }

    /// Select an arbitrary item and move thumbnail priority to its local neighborhood. This is the
    /// path used by taps in the filmstrip and source browser; keyboard navigation uses the methods
    /// above so both paths apply the same policy.
    func select(at index: Int) {
        guard isActive, items.indices.contains(index) else { return }
        selectedIndex = index
        reprioritizeThumbnails()
    }

    /// Clear the in-session collection (e.g. when opening a one-off single
    /// image). The persisted source-folder bookmark is left intact so it still
    /// restores on next launch; only the live browsing state is dropped.
    func clear() {
        cancelThumbnailWork()
        items = []
        selectedIndex = 0
        isActive = false
        sourceFolderURL = nil
    }

    // MARK: - Thumbnail generation

    /// Fill in each item's thumbnail through the bounded scheduler. Work is ranked around the
    /// selected photo and the decode itself stays detached from the main actor.
    private func generateThumbnails() {
        enqueueThumbnails()
    }

    private func enqueueThumbnails() {
        thumbnailGeneration &+= 1
        let generation = thumbnailGeneration

        for (index, item) in items.enumerated() where item.thumbnail == nil {
            let id = thumbnailJobID(for: item)
            guard !scheduler.contains(id) else {
                scheduler.updatePriority(for: id, to: priority(for: index))
                continue
            }
            enqueueThumbnail(for: item, at: index, generation: generation)
        }
    }

    private func reprioritizeThumbnails() {
        let keep = Set(items.enumerated().compactMap { index, item -> ImageWorkScheduler.JobID? in
            guard item.thumbnail == nil, distance(from: index) <= 2 else { return nil }
            return thumbnailJobID(for: item)
        })

        let obsolete = thumbnailJobIDs.subtracting(keep)
        scheduler.cancel(ids: obsolete)
        thumbnailJobIDs.subtract(obsolete)

        for (index, item) in items.enumerated() where item.thumbnail == nil {
            let id = thumbnailJobID(for: item)
            guard keep.contains(id) else { continue }
            if scheduler.contains(id) {
                scheduler.updatePriority(for: id, to: priority(for: index))
            } else {
                // The operation was dropped by the bounded queue. Re-admit only useful work after
                // navigation; the scheduler may still drop it if the neighborhood is full.
                enqueueThumbnail(for: item, at: index, generation: thumbnailGeneration)
            }
        }
        fillThumbnailQueue()
    }

    private func enqueueThumbnail(
        for item: Item, at index: Int, generation: UInt64
    ) {
        let id = thumbnailJobID(for: item)
        let url = item.url
        let data = item.imageData
        let itemID = item.id
        scheduler.enqueue(id: id, lane: .thumbnail, priority: priority(for: index)) { [weak self] in
            let thumbnail: NSImage?
            if let url {
                thumbnail = await Task.detached { Thumbnails.generate(from: url) }.value
            } else if let data {
                thumbnail = await Task.detached { Thumbnails.generate(from: data) }.value
            } else {
                thumbnail = nil
            }
            guard !Task.isCancelled else { return }
            self?.applyThumbnail(thumbnail, itemID: itemID, generation: generation)
        }
        if scheduler.contains(id) {
            thumbnailJobIDs.insert(id)
        }
    }

    private func applyThumbnail(_ thumbnail: NSImage?, itemID: UUID, generation: UInt64) {
        guard generation == thumbnailGeneration,
              let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        thumbnailJobIDs.remove(thumbnailJobID(for: items[index]))
        items[index].thumbnail = thumbnail
        fillThumbnailQueue()
    }

    /// Admit the next useful work after a worker finishes. The scan can discover thousands of files,
    /// but only the bounded scheduler queue is ever populated at once. Candidates are ordered by
    /// the same neighborhood policy used for navigation so a replenishment cannot push adjacent
    /// photos behind folder tail work.
    private func fillThumbnailQueue() {
        let candidates = items.indices
            .filter { items[$0].thumbnail == nil }
            .sorted {
                let lhs = priority(for: $0)
                let rhs = priority(for: $1)
                if lhs != rhs { return lhs.rawValue < rhs.rawValue }
                return distance(from: $0) < distance(from: $1)
            }

        for index in candidates {
            guard scheduler.canQueueThumbnail else { return }
            let item = items[index]
            let id = thumbnailJobID(for: item)
            guard !scheduler.contains(id) else { continue }
            enqueueThumbnail(for: item, at: index, generation: thumbnailGeneration)
        }
    }

    private func cancelThumbnailWork() {
        thumbnailGeneration &+= 1
        scheduler.cancel(ids: thumbnailJobIDs)
        thumbnailJobIDs.removeAll()
    }

    private func thumbnailJobID(for item: Item) -> ImageWorkScheduler.JobID {
        if let url = item.url {
            return ImageWorkScheduler.JobID("thumbnail:url:\(url.standardizedFileURL.path)")
        }
        return ImageWorkScheduler.JobID("thumbnail:item:\(item.id.uuidString)")
    }

    private func distance(from index: Int) -> Int {
        abs(index - selectedIndex)
    }

    private func priority(for index: Int) -> ImageWorkScheduler.Priority {
        switch distance(from: index) {
        case 0...2: return .adjacentFilmstrip
        case 3...12: return .visibleGrid
        default: return .background
        }
    }
}
