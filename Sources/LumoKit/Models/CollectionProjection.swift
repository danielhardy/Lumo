import Foundation

/// Pure projections used by collection views.
///
/// `ImageCollection` remains the owner of mutable scan/import/selection state. Keeping these
/// derived views as value functions gives the library and grid a small, independently testable seam
/// and makes it explicit that thumbnail arrival must not alter selection authority.
enum CollectionProjection {
    struct Snapshot {
        let filteredIndices: [Int]
        let thumbnailEntries: [ImageCollection.ThumbnailEntry]
    }

    /// Memoizes projections that are shared by the grid, filmstrip, and collection commands.
    /// Thumbnail changes intentionally do not alter either revision, so a completed cell does not
    /// make a large library walk its full item array again.
    struct Cache {
        private var key: Key?
        private var value: Snapshot?
        private(set) var rebuildCount = 0

        private struct Key: Equatable {
            let collectionRevision: UInt64
            let filterRevision: UInt64
        }

        mutating func snapshot(
            items: [ImageCollection.Item],
            filter: LibraryFilter,
            collectionRevision: UInt64,
            filterRevision: UInt64,
            pendingSlots: [ImageCollection.PendingImportSlot],
            itemIndices: [PhotoAssetID: Int],
            overflowIDs: Set<PhotoAssetID>
        ) -> Snapshot {
            let nextKey = Key(
                collectionRevision: collectionRevision,
                filterRevision: filterRevision
            )
            if key == nextKey, let value {
                return value
            }

            let filteredIndices = CollectionProjection.filteredIndices(items: items, filter: filter)
            let thumbnailEntries = CollectionProjection.thumbnailEntries(
                items: items,
                filter: filter,
                pendingSlots: pendingSlots,
                itemIndices: itemIndices,
                overflowIDs: overflowIDs,
                filteredIndices: filteredIndices
            )
            let nextValue = Snapshot(
                filteredIndices: filteredIndices,
                thumbnailEntries: thumbnailEntries
            )
            key = nextKey
            value = nextValue
            rebuildCount += 1
            return nextValue
        }
    }

    static func selectedIndices(
        items: [ImageCollection.Item],
        selection: LibrarySelectionModel
    ) -> [Int] {
        items.indices.filter { selection.selectedIDs.contains(items[$0].id) }
    }

    static func filteredIndices(
        items: [ImageCollection.Item],
        filter: LibraryFilter
    ) -> [Int] {
        items.indices.filter { index in
            filter.matches(flag: items[index].asset.flag, rating: items[index].asset.rating)
        }
    }

    static func filteredItems(
        items: [ImageCollection.Item],
        filter: LibraryFilter
    ) -> [ImageCollection.Item] {
        filteredIndices(items: items, filter: filter).map { items[$0] }
    }

    static func thumbnailEntries(
        items: [ImageCollection.Item],
        filter: LibraryFilter,
        pendingSlots: [ImageCollection.PendingImportSlot],
        itemIndices: [PhotoAssetID: Int],
        overflowIDs: Set<PhotoAssetID>,
        filteredIndices: [Int]? = nil
    ) -> [ImageCollection.ThumbnailEntry] {
        guard !pendingSlots.isEmpty else {
            let indices = filteredIndices ?? Self.filteredIndices(items: items, filter: filter)
            return indices.map { index in
                ImageCollection.ThumbnailEntry(
                    id: items[index].id,
                    itemIndex: index,
                    placeholder: nil,
                    aspectRatio: items[index].libraryAspectRatio
                )
            }
        }

        let reservedEntries = pendingSlots.compactMap { slot in
            guard let assetID = slot.assetID,
                  let itemIndex = itemIndices[assetID] else {
                return ImageCollection.ThumbnailEntry(
                    id: slot.id,
                    itemIndex: nil,
                    placeholder: slot,
                    aspectRatio: 4.0 / 3.0
                )
            }
            let item = items[itemIndex]
            guard filter.matches(flag: item.asset.flag, rating: item.asset.rating) else {
                return nil
            }
            return ImageCollection.ThumbnailEntry(
                id: assetID,
                itemIndex: itemIndex,
                placeholder: nil,
                aspectRatio: item.libraryAspectRatio
            )
        }

        let overflowEntries = items.indices.compactMap { itemIndex -> ImageCollection.ThumbnailEntry? in
            guard overflowIDs.contains(items[itemIndex].id),
                  filter.matches(
                      flag: items[itemIndex].asset.flag,
                      rating: items[itemIndex].asset.rating
                  ) else {
                return nil
            }
            let item = items[itemIndex]
            return ImageCollection.ThumbnailEntry(
                id: item.id,
                itemIndex: itemIndex,
                placeholder: nil,
                aspectRatio: item.libraryAspectRatio
            )
        }

        return reservedEntries + overflowEntries
    }
}
