import Foundation
import AppKit

/// Manages a collection of imported images with async thumbnail generation.
@MainActor
final class ImageCollection: ObservableObject {

    /// A Photos picker payload. The local identifier is preferred for durable edit identity; the
    /// ordinal fallback keeps two picker items with identical bytes distinct when the provider does
    /// not expose an identifier.
    struct PhotoImportItem: Sendable, Equatable {
        let name: String
        let data: Data
        let localIdentifier: String?

        init(name: String, data: Data, localIdentifier: String? = nil) {
            self.name = name
            self.data = data
            self.localIdentifier = localIdentifier
        }
    }

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

        /// The upright display ratio is available from deferred metadata as soon as ImageIO has
        /// read it. Until then use a photographic 4:3 placeholder, which keeps the first layout
        /// deterministic and independent of thumbnail completion order.
        var libraryAspectRatio: Double {
            guard let dimensions = asset.dimensions,
                  dimensions.width > 0, dimensions.height > 0 else { return 4.0 / 3.0 }
            return LibraryGridLayout.normalizedAspectRatio(
                Double(dimensions.width) / Double(dimensions.height)
            )
        }

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
    @Published private(set) var selection = LibrarySelectionModel()
    @Published var isActive: Bool = false
    @Published var isScanning: Bool = false
    @Published private(set) var scanWarnings: [ScanWarning] = []
    @Published private(set) var filter = LibraryFilter.all
    /// Changes only when the ordered filtered collection changes, not when deferred metadata
    /// updates an existing item. Library mosaic geometry uses this to avoid rebuilding rows for
    /// each metadata arrival.
    @Published private(set) var libraryLayoutRevision: UInt64 = 0
    /// The persistent source folder, if one is set (nil for Photos imports or
    /// one-off single-image opens).
    @Published var sourceFolderURL: URL?

    private static let bookmarkKey = "imageSourceFolderBookmark"
    private static let cullingStateKey = "imageLibraryCullingState"
    private struct PersistedCullingState: Codable, Equatable {
        let rating: Int
        let flag: PhotoFlag

        var libraryState: PhotoAssetLibraryState {
            PhotoAssetLibraryState(rating: rating, flag: flag)
        }
    }

    private let defaults: UserDefaults
    private var persistedCullingStates: [String: PersistedCullingState]
    private struct CullingChange {
        let itemID: PhotoAssetID
        let oldState: PhotoAssetLibraryState
        let activeIDBefore: PhotoAssetID?
    }
    private var cullingUndoStack: [CullingChange] = []
    private var scanTask: Task<Void, Never>?
    private var scanGeneration: UInt64 = 0
    private var metadataTask: Task<Void, Never>?
    private var metadataContinuation: AsyncStream<MetadataRequest>.Continuation?
    private let scheduler: ImageWorkScheduler
    private var thumbnailJobIDs: Set<ImageWorkScheduler.JobID> = []
    private var thumbnailGeneration: UInt64 = 0
    /// Grid cells opt into this mode when they appear. The fallback mode keeps the inherited
    /// filmstrip/source-browser behavior, while the grid admits only its visible/prefetched cells.
    private var isThumbnailDemandDriven = false
    private var thumbnailDemandIDs: Set<PhotoAssetID> = []
    private var thumbnailDemandPriorities: [PhotoAssetID: ImageWorkScheduler.Priority] = [:]
    /// The selected filmstrip item and its small neighborhood stay warm even when SwiftUI has not
    /// materialized those cells yet. This keeps ←/→ stepping from waiting on a cold thumbnail.
    private var preparedThumbnailIDs: Set<PhotoAssetID> = []
    /// Folder whose security scope we hold open, released when we move on.
    private var scopedURL: URL?

    init(
        scheduler: ImageWorkScheduler = ImageWorkScheduler(),
        defaults: UserDefaults = .standard
    ) {
        self.scheduler = scheduler
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.cullingStateKey),
           let states = try? JSONDecoder().decode([String: PersistedCullingState].self, from: data) {
            self.persistedCullingStates = states
        } else {
            self.persistedCullingStates = [:]
        }
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

    /// The current edit-transfer destinations, in source order. The active item remains separate
    /// from this selection so command-click can prepare a batch without changing the open photo.
    var selectedIndices: [Int] {
        items.indices.filter { selection.selectedIDs.contains(items[$0].id) }
    }

    var selectedItems: [Item] {
        selectedIndices.map { items[$0] }
    }

    var filteredItems: [Item] {
        items.filter { filter.matches(flag: $0.asset.flag, rating: $0.asset.rating) }
    }

    var filteredIndices: [Int] {
        items.indices.filter { index in
            filter.matches(flag: items[index].asset.flag, rating: items[index].asset.rating)
        }
    }

    var filteredItemCount: Int { filteredIndices.count }

    func setFilter(_ filter: LibraryFilter) {
        guard self.filter != filter else { return }
        self.filter = filter
        invalidateLibraryLayout()
        reconcileFilteredSelection()
    }

    func clearFilter() {
        setFilter(.all)
    }

    /// Set the focused asset's flag. Pick/reject keyboard workflows advance to the next visible
    /// asset; callers can opt out for a toolbar or programmatic edit.
    @discardableResult
    func setFlag(_ flag: PhotoFlag, for id: PhotoAssetID? = nil, advance shouldAdvance: Bool = false) -> Bool {
        guard let itemID = id ?? selectedItem?.id,
              let index = items.firstIndex(where: { $0.id == itemID }) else { return false }
        let oldState = items[index].asset.libraryState
        guard oldState.flag != flag else {
            if shouldAdvance { advance(from: index) }
            return false
        }
        recordCullingChange(itemID: itemID, oldState: oldState)
        items[index].asset.flag = flag
        invalidateLibraryLayout()
        persistCullingState(for: items[index].asset)
        if shouldAdvance { advance(from: index) }
        if !filteredIndices.contains(selectedIndex) { reconcileFilteredSelection() }
        return true
    }

    /// Set the focused asset's star rating without advancing the browsing focus.
    @discardableResult
    func setRating(_ rating: Int, for id: PhotoAssetID? = nil) -> Bool {
        guard let itemID = id ?? selectedItem?.id,
              let index = items.firstIndex(where: { $0.id == itemID }) else { return false }
        let clamped = min(max(rating, 0), 5)
        let oldState = items[index].asset.libraryState
        guard oldState.rating != clamped else { return false }
        recordCullingChange(itemID: itemID, oldState: oldState)
        items[index].asset.rating = clamped
        invalidateLibraryLayout()
        persistCullingState(for: items[index].asset)
        if !filteredIndices.contains(selectedIndex) { reconcileFilteredSelection() }
        return true
    }

    var canUndoCulling: Bool { !cullingUndoStack.isEmpty }

    @discardableResult
    func undoLastCullingChange() -> Bool {
        guard let change = cullingUndoStack.popLast(),
              let index = items.firstIndex(where: { $0.id == change.itemID }) else { return false }
        items[index].asset.libraryState = change.oldState
        invalidateLibraryLayout()
        persistCullingState(for: items[index].asset)
        if let activeID = change.activeIDBefore,
           filteredIndices.contains(where: { items[$0].id == activeID }) {
            var next = selection
            next.focus(activeID, in: items.map(\.id))
            selection = next
            syncSelectedIndex()
        } else {
            reconcileFilteredSelection()
        }
        return true
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
        invalidateLibraryLayout()
        selectedIndex = 0
        selection.clear()
        thumbnailDemandIDs.removeAll()
        thumbnailDemandPriorities.removeAll()
        preparedThumbnailIDs.removeAll()
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
                            asset: restoredCullingState(
                                for: PhotoAsset(url: discovery.url, filename: discovery.displayName)
                            ),
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
                    self.invalidateLibraryLayout()
                    self.reconcileSelection()
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
            invalidateLibraryLayout()
            reconcileSelection()
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
        beginDataImport()
        for (ordinal, item) in dataItems.enumerated() {
            appendDataImport(
                PhotoImportItem(name: item.name, data: item.data), ordinal: ordinal
            )
        }
        finishDataImport()
    }

    /// Start a streamed Photos import. Items are published as they arrive instead of waiting for
    /// the picker to transfer the entire selection, so the first asset can be opened immediately
    /// and one failed/cancelled transfer does not discard earlier successes.
    func beginDataImport() {
        scanGeneration &+= 1
        cancelThumbnailWork()
        scanTask?.cancel()
        scanTask = nil
        stopMetadataLoading()
        items = []
        invalidateLibraryLayout()
        selectedIndex = 0
        selection.clear()
        isThumbnailDemandDriven = false
        thumbnailDemandIDs.removeAll()
        thumbnailDemandPriorities.removeAll()
        preparedThumbnailIDs.removeAll()
        isScanning = false
        scanWarnings = []
        startMetadataLoading()
    }

    /// Append one full-fidelity Photos payload to the live collection. The Data is retained as the
    /// original source bytes; thumbnails are generated separately from the embedded preview and
    /// never replace the source.
    @discardableResult
    func appendDataImport(_ item: PhotoImportItem, ordinal: Int) -> PhotoAssetID {
        let identifier = item.localIdentifier.map(PhotoAssetID.photos)
            ?? .imported(data: item.data, name: item.name, ordinal: ordinal)
        let source = PhotoAssetSource(data: item.data, id: identifier)
        let asset = restoredCullingState(for: PhotoAsset(
            source: source,
            filename: item.name,
            fileType: URL(fileURLWithPath: item.name).pathExtension
        ))
        var interval = LumoSignpostInterval(
            .photoCollectionInsert,
            context: LumoTraceContext(sourceFingerprint: identifier.raw, quality: "photosImport")
        )
        items.append(Item(asset: asset, metadata: nil))
        invalidateLibraryLayout()
        reconcileSelection()
        isActive = true
        enqueueMetadata(for: items[items.count - 1], generation: scanGeneration)
        enqueueThumbnails()
        interval.end()
        return identifier
    }

    /// Finish a streamed import after the picker task has transferred all items it can. Deferred
    /// metadata still drains the values already queued before its stream is closed.
    func finishDataImport() {
        metadataContinuation?.finish()
        metadataContinuation = nil
        enqueueThumbnails()
    }

    /// Number of source items currently retained by a streamed import.
    var importedDataCount: Int { items.count }

    // MARK: - Navigation

    /// Begin viewport-driven thumbnail admission for the library grid. Existing completed
    /// thumbnails are retained, while queued work is cancelled so a scan of a large folder cannot
    /// continue filling memory with cells the user has not seen.
    func beginThumbnailDemand() {
        guard !isThumbnailDemandDriven else { return }
        isThumbnailDemandDriven = true
        cancelThumbnailWork()
        prepareAdjacentThumbnails(around: selectedIndex)
        fillThumbnailQueue()
    }

    /// Request the thumbnail for a cell that SwiftUI has materialized. LazyVGrid's own small
    /// prefetch window means this naturally covers visible and near-visible cells only.
    func requestThumbnail(
        for id: PhotoAssetID,
        priority: ImageWorkScheduler.Priority = .visibleGrid
    ) {
        guard isThumbnailDemandDriven,
              let index = items.firstIndex(where: { $0.id == id }),
              items[index].thumbnail == nil else { return }
        thumbnailDemandIDs.insert(id)
        thumbnailDemandPriorities[id] = priority
        let jobID = thumbnailJobID(for: items[index])
        if !scheduler.contains(jobID) {
            enqueueThumbnail(
                for: items[index], at: index, generation: thumbnailGeneration, priority: priority
            )
        } else {
            scheduler.updatePriority(for: jobID, to: priority)
        }
    }

    /// Release a cell that has left the grid's materialized window. A finished thumbnail is kept
    /// as a cheap cache in the item; only in-flight work is cancelled.
    func releaseThumbnail(for id: PhotoAssetID) {
        guard isThumbnailDemandDriven else { return }
        thumbnailDemandIDs.remove(id)
        thumbnailDemandPriorities.removeValue(forKey: id)
        guard !preparedThumbnailIDs.contains(id) else { return }
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].thumbnail == nil else {
            return
        }
        let jobID = thumbnailJobID(for: items[index])
        scheduler.cancel(id: jobID)
        thumbnailJobIDs.remove(jobID)
        items[index].asset.thumbnailState = .notRequested
    }

    func selectAll() {
        var next = selection
        next.selectAll(in: filteredItems.map(\.id))
        selection = next
        syncSelectedIndex()
        prepareAdjacentThumbnails(around: selectedIndex)
        reprioritizeThumbnails()
    }

    func select(at index: Int, modifiers: LibrarySelectionModel.Modifiers = []) {
        guard isActive, items.indices.contains(index), filter.matches(
            flag: items[index].asset.flag, rating: items[index].asset.rating
        ) else { return }
        var next = selection
        next.click(items[index].id, in: filteredItems.map(\.id), modifiers: modifiers)
        selection = next
        syncSelectedIndex()
        prepareAdjacentThumbnails(around: selectedIndex)
        reprioritizeThumbnails()
    }

    func selectNext() {
        guard let nextIndex = filteredIndices.first(where: { $0 > selectedIndex }) else { return }
        select(at: nextIndex)
    }

    func selectPrevious() {
        guard let previousIndex = filteredIndices.last(where: { $0 < selectedIndex }) else { return }
        select(at: previousIndex)
    }

    /// Select an arbitrary item and move thumbnail priority to its local neighborhood. This is the
    /// path used by taps in the filmstrip and source browser; keyboard navigation uses the methods
    /// above so both paths apply the same policy.
    func select(at index: Int) {
        select(at: index, modifiers: [])
    }

    /// Select an item for edit-transfer without opening it. This compatibility seam keeps tests and
    /// non-view callers independent of the modifier bitset used by the library UI.
    func setSelection(at index: Int, additive: Bool = false) {
        select(at: index, modifiers: additive ? [.command] : [])
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
        invalidateLibraryLayout()
        selectedIndex = 0
        selection.clear()
        isThumbnailDemandDriven = false
        thumbnailDemandIDs.removeAll()
        thumbnailDemandPriorities.removeAll()
        preparedThumbnailIDs.removeAll()
        isActive = false
        isScanning = false
        scanWarnings = []
        sourceFolderURL = nil
    }

    private func invalidateLibraryLayout() {
        libraryLayoutRevision &+= 1
    }

    // MARK: - Thumbnail generation

    /// Fill in each item's thumbnail through the bounded scheduler. Work is ranked around the
    /// selected photo and the decode itself stays detached from the main actor.
    private func generateThumbnails() {
        enqueueThumbnails()
    }

    private func enqueueThumbnails() {
        let generation = thumbnailGeneration

        if isThumbnailDemandDriven {
            fillThumbnailQueue()
            return
        }

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
        let keep: Set<ImageWorkScheduler.JobID>
        if isThumbnailDemandDriven {
            keep = Set(items.compactMap { item in
                isThumbnailDemanded(item.id) && item.thumbnail == nil
                    ? thumbnailJobID(for: item) : nil
            })
        } else {
            keep = Set(items.enumerated().compactMap { index, item -> ImageWorkScheduler.JobID? in
                guard item.thumbnail == nil, distance(from: index) <= 2 else { return nil }
                return thumbnailJobID(for: item)
            })
        }

        let obsolete = thumbnailJobIDs.subtracting(keep)
        scheduler.cancel(ids: obsolete)
        thumbnailJobIDs.subtract(obsolete)

        for (index, item) in items.enumerated() where item.thumbnail == nil {
            let id = thumbnailJobID(for: item)
            guard keep.contains(id) else { continue }
            if scheduler.contains(id) {
                scheduler.updatePriority(
                    for: id, to: priority(for: index, requested: thumbnailDemandPriorities[item.id])
                )
            } else {
                // The operation was dropped by the bounded queue. Re-admit only useful work after
                // navigation; the scheduler may still drop it if the neighborhood is full.
                enqueueThumbnail(
                    for: item, at: index, generation: thumbnailGeneration,
                    priority: thumbnailDemandPriorities[item.id]
                )
            }
        }
        fillThumbnailQueue()
    }

    private func enqueueThumbnail(
        for item: Item, at index: Int, generation: UInt64,
        priority requestedPriority: ImageWorkScheduler.Priority? = nil
    ) {
        let id = thumbnailJobID(for: item)
        let url = item.url
        let data = item.imageData
        let itemID = item.id
        scheduler.enqueue(
            id: id, lane: .thumbnail,
            priority: priority(for: index, requested: requestedPriority)
        ) { [weak self] in
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
            .filter {
                items[$0].thumbnail == nil
                    && (!isThumbnailDemandDriven || isThumbnailDemanded(items[$0].id))
            }
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
            enqueueThumbnail(
                for: item, at: index, generation: thumbnailGeneration,
                priority: thumbnailDemandPriorities[item.id]
            )
        }
    }

    private func cancelThumbnailWork() {
        thumbnailGeneration &+= 1
        scheduler.cancel(ids: thumbnailJobIDs)
        thumbnailJobIDs.removeAll()
    }

    /// Keep the selected photo and up to two visible neighbors eligible for thumbnail work. The
    /// IDs are tracked separately from viewport demand so a cell disappearing from the lazy stack
    /// cannot cancel a photo that keyboard navigation is about to use.
    private func prepareAdjacentThumbnails(around index: Int) {
        guard isThumbnailDemandDriven else { return }
        let prepared = Set(items.indices.filter { abs($0 - index) <= 2 }.map { items[$0].id })
        let obsolete = preparedThumbnailIDs.subtracting(prepared)
        preparedThumbnailIDs = prepared
        thumbnailDemandPriorities = thumbnailDemandPriorities.filter { id, _ in
            thumbnailDemandIDs.contains(id) || prepared.contains(id)
        }
        for id in prepared {
            thumbnailDemandPriorities[id] = .adjacentFilmstrip
        }
        for id in obsolete where !thumbnailDemandIDs.contains(id) {
            guard let item = items.first(where: { $0.id == id }), item.thumbnail == nil else { continue }
            scheduler.cancel(id: thumbnailJobID(for: item))
            thumbnailJobIDs.remove(thumbnailJobID(for: item))
        }
    }

    private func isThumbnailDemanded(_ id: PhotoAssetID) -> Bool {
        thumbnailDemandIDs.contains(id) || preparedThumbnailIDs.contains(id)
    }

    private func reconcileSelection() {
        var next = selection
        let ids = items.map(\.id)
        next.reconcile(with: ids)
        // `reconcile` alone can leave the selection empty (e.g. the sole selected item was just
        // removed as unreadable) even though other items remain; fall back to the first one so a
        // non-empty library always keeps an active item, matching native list behavior.
        if next.isEmpty, let first = ids.first {
            next.click(first, in: ids)
        }
        selection = next
        syncSelectedIndex()
    }

    private func reconcileFilteredSelection() {
        let visible = filteredIndices
        guard let firstVisible = visible.first else {
            // Preserve the selection and active asset for when the filter is cleared. An empty
            // result has no visible navigation target, but it must not erase culling state.
            return
        }
        guard !visible.contains(selectedIndex) else { return }
        var next = selection
        next.focus(items[firstVisible].id, in: items.map(\.id))
        selection = next
        syncSelectedIndex()
        reprioritizeThumbnails()
    }

    private func advance(from index: Int) {
        guard let nextIndex = filteredIndices.first(where: { $0 > index }) else { return }
        select(at: nextIndex)
    }

    private func recordCullingChange(itemID: PhotoAssetID, oldState: PhotoAssetLibraryState) {
        cullingUndoStack.append(CullingChange(
            itemID: itemID,
            oldState: oldState,
            activeIDBefore: selection.activeID
        ))
        // Keep a useful bounded history for long culling sessions.
        if cullingUndoStack.count > 100 { cullingUndoStack.removeFirst() }
    }

    private func persistCullingState(for asset: PhotoAsset) {
        persistedCullingStates[asset.id.raw] = PersistedCullingState(
            rating: asset.rating,
            flag: asset.flag
        )
        guard let data = try? JSONEncoder().encode(persistedCullingStates) else { return }
        defaults.set(data, forKey: Self.cullingStateKey)
    }

    private func restoredCullingState(for asset: PhotoAsset) -> PhotoAsset {
        guard let persisted = persistedCullingStates[asset.id.raw] else { return asset }
        var restored = asset
        restored.libraryState = persisted.libraryState
        return restored
    }

    private func syncSelectedIndex() {
        guard let activeID = selection.activeID,
              let index = items.firstIndex(where: { $0.id == activeID }) else {
            if items.isEmpty { selectedIndex = 0 }
            return
        }
        selectedIndex = index
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

    private func priority(
        for index: Int,
        requested requestedPriority: ImageWorkScheduler.Priority? = nil
    ) -> ImageWorkScheduler.Priority {
        if let requestedPriority { return requestedPriority }
        switch distance(from: index) {
        case 0...2: return .adjacentFilmstrip
        case 3...12: return .visibleGrid
        default: return .background
        }
    }
}
