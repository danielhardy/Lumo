import Foundation
import AppKit

/// Manages a collection of imported images with async thumbnail generation.
@MainActor
final class ImageCollection: ObservableObject {

    struct Item: Identifiable {
        var asset: PhotoAsset
        var thumbnail: NSImage?
        /// Filled after discovery. A nil value means deferred metadata work has not completed.
        var metadata: ImageMetadata? = nil
        /// Relative directory from the source-folder root ("" for top level).
        /// Drives the grouped file browser; empty for Photos imports.
        var subfolder: String = ""

        var id: PhotoAssetID { asset.id }
        var url: URL? { asset.url }
        var displayName: String { asset.filename }
        var imageData: Data? { asset.source.data }

        init(
            asset: PhotoAsset,
            thumbnail: NSImage? = nil,
            metadata: ImageMetadata? = nil,
            subfolder: String = ""
        ) {
            self.asset = asset
            self.thumbnail = thumbnail
            self.metadata = metadata
            self.subfolder = subfolder
        }

        /// UI compatibility initializer. The durable record is built first; the AppKit thumbnail
        /// remains a presentation concern of `ImageCollection.Item`.
        init(
            url: URL?,
            displayName: String,
            thumbnail: NSImage? = nil,
            imageData: Data?,
            metadata: ImageMetadata? = nil,
            subfolder: String = ""
        ) {
            if let url {
                self.init(asset: PhotoAsset(url: url, filename: displayName), thumbnail: thumbnail,
                          metadata: metadata, subfolder: subfolder)
            } else if let imageData {
                self.init(asset: PhotoAsset(data: imageData, filename: displayName), thumbnail: thumbnail,
                          metadata: metadata, subfolder: subfolder)
            } else {
                preconditionFailure("An image item needs either a URL or image data")
            }
        }
    }

    /// A non-fatal problem encountered while a folder is being discovered or its deferred data is
    /// loaded. The scan keeps publishing usable files when one file disappears or is malformed.
    struct ScanWarning: Identifiable, Equatable, Sendable {
        let id: String
        let message: String

        init(id: String, message: String) {
            self.id = id
            self.message = message
        }
    }

    @Published var items: [Item] = []
    @Published var selectedIndex: Int = 0
    @Published var isActive: Bool = false
    @Published var isScanning: Bool = false
    @Published private(set) var scanWarnings: [ScanWarning] = []
    /// The persistent source folder, if one is set (nil for Photos imports or
    /// one-off single-image opens).
    @Published var sourceFolderURL: URL?

    private static let bookmarkKey = "imageSourceFolderBookmark"
    private var scanTask: Task<Void, Never>?
    private var scanGeneration: UInt64 = 0
    private var metadataTask: Task<Void, Never>?
    private var metadataContinuation: AsyncStream<MetadataRequest>.Continuation?
    private let scheduler: ImageWorkScheduler
    private var thumbnailJobIDs: Set<ImageWorkScheduler.JobID> = []
    private var thumbnailGeneration: UInt64 = 0
    /// Folder whose security scope we hold open, released when we move on.
    private var scopedURL: URL?

    init(scheduler: ImageWorkScheduler = ImageWorkScheduler()) {
        self.scheduler = scheduler
    }

    deinit {
        metadataContinuation?.finish()
        metadataTask?.cancel()
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

    /// Wait for the in-flight folder scan and its deferred metadata work to finish, so callers
    /// that need a complete asset snapshot (open the first image, say) can do so without racing it.
    func scanCompletion() async {
        await scanTask?.value
        await metadataTask?.value
    }

    /// Wait for metadata already queued by the current scan/import to finish. Thumbnail work is
    /// intentionally not included: it is demand-prioritized and may continue while the user edits.
    func metadataCompletion() async {
        await metadataTask?.value
    }

    /// Scan a folder recursively for supported images, recording each file's
    /// relative subfolder so the browser can group them. Items are ordered by
    /// subfolder, then natural filename order.
    ///
    /// The enumeration runs off the main actor — a deep folder on a slow or
    /// network volume would otherwise stall the window, and this runs during
    /// app launch when a source folder is restored.
    func loadFromFolder(_ url: URL) {
        scanGeneration &+= 1
        let generation = scanGeneration
        cancelThumbnailWork()
        scanTask?.cancel()
        stopMetadataLoading()
        items = []
        selectedIndex = 0
        isActive = false
        isScanning = true
        scanWarnings = []
        startMetadataLoading()

        scanTask = Task { [weak self] in
            guard let self else { return }
            var interval = LumoSignpostInterval(
                .scan,
                context: LumoTraceContext(sourceFingerprint: url.standardizedFileURL.path, quality: "background")
            )
            defer { interval.end() }

            var knownItems: [String: Item] = [:]
            let stream = Self.discoveryStream(url)
            for await event in stream {
                guard !Task.isCancelled, self.scanGeneration == generation else { return }
                switch event {
                case .warning(let warning):
                    self.addScanWarning(warning)
                case .batch(let discoveries):
                    for discovery in discoveries {
                        let path = discovery.url.standardizedFileURL.path
                        let item = knownItems[path] ?? Item(
                            asset: PhotoAsset(url: discovery.url, filename: discovery.displayName),
                            thumbnail: nil,
                            metadata: nil,
                            subfolder: discovery.subfolder
                        )
                        knownItems[path] = item
                        if !self.items.contains(where: { $0.id == item.id }) {
                            self.items.append(item)
                        }
                        self.enqueueMetadata(for: item, generation: generation)
                    }

                    // Sorting the accumulated prefix on every batch keeps the final ordering
                    // deterministic while still making the first useful rows visible immediately.
                    self.items.sort(by: Self.itemPrecedes)
                    self.isActive = !self.items.isEmpty
                    self.generateThumbnails()
                    // Let SwiftUI and cancellation run between batches even on a fast local disk.
                    await Task.yield()
                }
            }

            guard !Task.isCancelled, self.scanGeneration == generation else { return }
            self.isScanning = false
            self.metadataContinuation?.finish()
            self.metadataContinuation = nil
        }
    }

    private struct DiscoveredItem: Sendable {
        let url: URL
        let displayName: String
        let subfolder: String
    }

    private enum DiscoveryEvent: Sendable {
        case batch([DiscoveredItem])
        case warning(String)
    }

    private struct MetadataRequest: Sendable {
        let itemID: PhotoAssetID
        let generation: UInt64
        let name: String
        let source: ImageSource.Backing
    }

    private enum MetadataOutcome: Sendable {
        case success(ImageMetadata)
        case failure(String)
    }

    private nonisolated static let scanBatchSize = 32

    /// Discover file names and relative folders off the main actor. This deliberately does not read
    /// image properties: discovery is the cheap stage, while dimensions and capture metadata are
    /// queued separately after each batch is published.
    private nonisolated static func discoveryStream(_ url: URL) -> AsyncStream<DiscoveryEvent> {
        let (stream, continuation) = AsyncStream<DiscoveryEvent>.makeStream()
        let producer = Task.detached {
            let fm = FileManager.default
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                _ = continuation.yield(.warning("Can't find “\(url.lastPathComponent)” — it may have been moved or renamed."))
                continuation.finish()
                return
            }
            guard fm.isReadableFile(atPath: url.path) else {
                _ = continuation.yield(.warning("No permission to read “\(url.lastPathComponent)”."))
                continuation.finish()
                return
            }
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                _ = continuation.yield(.warning("Can't read “\(url.lastPathComponent)”."))
                continuation.finish()
                return
            }

            let rootPath = url.resolvingSymlinksInPath().path
            let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            var batch: [DiscoveredItem] = []
            while let fileURL = enumerator.nextObject() as? URL {
                guard !Task.isCancelled else { break }
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                let ext = fileURL.pathExtension.lowercased()
                guard ImageDecoder.supportedExtensions.contains(ext) else { continue }

                if !fm.isReadableFile(atPath: fileURL.path) {
                    _ = continuation.yield(.warning("Skipping unreadable image “\(fileURL.lastPathComponent)”."))
                    continue
                }

                let name = fileURL.deletingPathExtension().lastPathComponent
                let dir = fileURL.deletingLastPathComponent().resolvingSymlinksInPath().path
                let subfolder = dir == rootPath || dir.hasPrefix(rootPrefix)
                    ? String(dir.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    : ""
                batch.append(DiscoveredItem(url: fileURL, displayName: name, subfolder: subfolder))
                if batch.count == scanBatchSize {
                    guard case .enqueued = continuation.yield(.batch(batch)) else { return }
                    batch.removeAll(keepingCapacity: true)
                    await Task.yield()
                }
            }
            if !batch.isEmpty, !Task.isCancelled {
                _ = continuation.yield(.batch(batch))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in producer.cancel() }
        return stream
    }

    private nonisolated static func itemPrecedes(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.subfolder != rhs.subfolder {
            return lhs.subfolder.localizedStandardCompare(rhs.subfolder) == .orderedAscending
        }
        let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return (lhs.url?.standardizedFileURL.path ?? lhs.displayName)
            < (rhs.url?.standardizedFileURL.path ?? rhs.displayName)
    }

    // Legacy synchronous helper retained for compatibility with focused internal tests.
    private nonisolated static func scanFolder(_ url: URL) -> [DiscoveredItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Resolve symlinks on both sides so the prefix math holds even when the
        // root is itself a symlink (e.g. /tmp → /private/tmp).
        let rootPath = url.resolvingSymlinksInPath().path
        var newItems: [DiscoveredItem] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { return [] }
            let ext = fileURL.pathExtension.lowercased()
            guard ImageDecoder.supportedExtensions.contains(ext) else { continue }
            let dir = fileURL.deletingLastPathComponent().resolvingSymlinksInPath().path
            let subfolder = dir.hasPrefix(rootPath)
                ? String(dir.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : ""
            let name = fileURL.deletingPathExtension().lastPathComponent
            newItems.append(DiscoveredItem(url: fileURL, displayName: name, subfolder: subfolder))
        }

        newItems.sort {
            if $0.subfolder != $1.subfolder {
                return $0.subfolder.localizedStandardCompare($1.subfolder) == .orderedAscending
            }
            let nameOrder = $0.displayName.localizedStandardCompare($1.displayName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.url.standardizedFileURL.path < $1.url.standardizedFileURL.path
        }
        return newItems
    }

    // MARK: - Deferred metadata

    private func startMetadataLoading() {
        let (stream, continuation) = AsyncStream<MetadataRequest>.makeStream()
        metadataContinuation = continuation
        metadataTask = Task.detached { [weak self] in
            for await request in stream {
                guard !Task.isCancelled else { return }
                let outcome = Self.readMetadata(request.source, name: request.name)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyMetadata(outcome, itemID: request.itemID, generation: request.generation)
                }
            }
        }
    }

    private func stopMetadataLoading() {
        metadataContinuation?.finish()
        metadataContinuation = nil
        metadataTask?.cancel()
        metadataTask = nil
    }

    private func enqueueMetadata(for item: Item, generation: UInt64) {
        guard let source = item.url.map(ImageSource.Backing.url)
            ?? item.imageData.map(ImageSource.Backing.data) else { return }
        _ = metadataContinuation?.yield(MetadataRequest(
            itemID: item.id,
            generation: generation,
            name: item.url?.lastPathComponent ?? item.displayName,
            source: source
        ))
    }

    private nonisolated static func readMetadata(
        _ source: ImageSource.Backing, name: String
    ) -> MetadataOutcome {
        switch source {
        case .url(let url):
            guard FileManager.default.isReadableFile(atPath: url.path),
                  let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(imageSource) > 0 else {
                return .failure("Skipping unreadable image “\(name)”.")
            }
            return .success(ImageMetadata.read(from: url))
        case .data(let data):
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(imageSource) > 0 else {
                return .failure("Skipping unreadable image “\(name)”.")
            }
            return .success(ImageMetadata.read(from: data))
        }
    }

    private func applyMetadata(_ outcome: MetadataOutcome, itemID: PhotoAssetID, generation: UInt64) {
        guard generation == scanGeneration,
              let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        switch outcome {
        case .success(let metadata):
            items[index].metadata = metadata
            items[index].asset.updateMetadata(from: metadata)
        case .failure(let warning):
            addScanWarning(warning)
            let item = items[index]
            scheduler.cancel(id: thumbnailJobID(for: item))
            thumbnailJobIDs.remove(thumbnailJobID(for: item))
            items.remove(at: index)
            selectedIndex = min(selectedIndex, max(0, items.count - 1))
            isActive = !items.isEmpty
        }
    }

    private func addScanWarning(_ message: String) {
        let id = message
        guard !scanWarnings.contains(where: { $0.id == id }) else { return }
        scanWarnings.append(ScanWarning(id: id, message: message))
    }

    // MARK: - Data import (from Photos picker)

    /// Adopt a set of Photos-picker payloads as the collection.
    ///
    /// **The second thumbnail site.** `generateThumbnails` below is the obvious one; this one builds
    /// its thumbnails inline and is easy to miss when the thumbnail path moves — which is why
    /// `docs/PHASE2_SPEC.md` §6 names both explicitly. Step 7 pointed both at `Thumbnails`.
    func addFromData(_ dataItems: [(name: String, data: Data)]) {
        scanGeneration &+= 1
        let generation = scanGeneration
        cancelThumbnailWork()
        scanTask?.cancel()
        scanTask = nil
        stopMetadataLoading()
        items = []
        selectedIndex = 0
        isScanning = false
        scanWarnings = []
        startMetadataLoading()

        var newItems: [Item] = []
        for item in dataItems {
            newItems.append(Item(
                asset: PhotoAsset(data: item.data, filename: item.name),
                metadata: nil
            ))
        }
        self.items = newItems
        self.isActive = !items.isEmpty
        for item in newItems { enqueueMetadata(for: item, generation: generation) }
        metadataContinuation?.finish()
        metadataContinuation = nil
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
        scanGeneration &+= 1
        cancelThumbnailWork()
        scanTask?.cancel()
        scanTask = nil
        stopMetadataLoading()
        items = []
        selectedIndex = 0
        isActive = false
        isScanning = false
        scanWarnings = []
        sourceFolderURL = nil
    }

    // MARK: - Thumbnail generation

    /// Fill in each item's thumbnail through the bounded scheduler. Work is ranked around the
    /// selected photo and the decode itself stays detached from the main actor.
    private func generateThumbnails() {
        enqueueThumbnails()
    }

    private func enqueueThumbnails() {
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
        if scheduler.contains(id), let currentIndex = items.firstIndex(where: { $0.id == itemID }) {
            thumbnailJobIDs.insert(id)
            items[currentIndex].asset.thumbnailState = .loading
        }
    }

    private func applyThumbnail(_ thumbnail: NSImage?, itemID: PhotoAssetID, generation: UInt64) {
        guard generation == thumbnailGeneration,
              let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        thumbnailJobIDs.remove(thumbnailJobID(for: items[index]))
        items[index].thumbnail = thumbnail
        items[index].asset.thumbnailState = thumbnail == nil ? .failed : .ready
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
        return ImageWorkScheduler.JobID("thumbnail:item:\(item.id.raw)")
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
