import AppKit
import Combine
import XCTest

@testable import LumoKit

/// Regression coverage for the library's two invalidation boundaries: collection projections are
/// rebuilt only when their inputs change, and a thumbnail is published by its own item rather than
/// by the collection containing thousands of items.
@MainActor
final class CollectionProjectionPerformanceTests: XCTestCase {

    func testProjectionCacheIsStableFor1KAnd10KLibraries() {
        for count in [1_000, 10_000] {
            let collection = ImageCollection()
            collection.items = makeItems(count: count)

            let start = DispatchTime.now().uptimeNanoseconds
            _ = collection.thumbnailEntries
            _ = collection.filteredIndices
            _ = collection.filteredItems
            let firstAccess = DispatchTime.now().uptimeNanoseconds

            for _ in 0..<20 {
                _ = collection.thumbnailEntries
                _ = collection.filteredIndices
                _ = collection.filteredItems
            }
            let end = DispatchTime.now().uptimeNanoseconds

            XCTAssertEqual(collection.projectionRebuildCount, 1)
            print(String(
                format: "LIBRARY_PROJECTION_PROFILE items=%d first_ms=%.1f repeated_ms=%.1f rebuilds=%d",
                count,
                Double(firstAccess - start) / 1_000_000,
                Double(end - firstAccess) / 1_000_000,
                collection.projectionRebuildCount
            ))
        }
    }

    func testThumbnailPublishesOnlyFromTheChangedItemAndKeepsProjectionCache() {
        let collection = ImageCollection()
        let items = makeItems(count: 3)
        collection.items = items
        _ = collection.thumbnailEntries
        let rebuildsBeforeThumbnail = collection.projectionRebuildCount

        var collectionChanges = 0
        var itemChanges = 0
        let collectionSubscription = collection.objectWillChange.sink { _ in
            collectionChanges += 1
        }
        let itemSubscription = items[1].objectWillChange.sink { _ in
            itemChanges += 1
        }

        items[1].thumbnail = NSImage(size: NSSize(width: 8, height: 8))
        _ = collection.thumbnailEntries

        XCTAssertEqual(itemChanges, 1)
        XCTAssertEqual(collectionChanges, 0)
        XCTAssertEqual(collection.projectionRebuildCount, rebuildsBeforeThumbnail)
        XCTAssertNil(items[0].thumbnail)
        XCTAssertNil(items[2].thumbnail)

        collectionSubscription.cancel()
        itemSubscription.cancel()
    }

    func testFilterRevisionRebuildsTheProjectionWithoutChangingItemIdentityOrder() {
        let collection = ImageCollection()
        let items = makeItems(count: 4)
        items[1].asset.rating = 4
        items[3].asset.rating = 2
        collection.items = items

        XCTAssertEqual(collection.thumbnailEntries.map(\.id), items.map(\.id))
        let initialRebuilds = collection.projectionRebuildCount

        collection.setFilter(LibraryFilter(
            flag: .all,
            rating: .minimum(3)
        ))

        XCTAssertEqual(collection.filteredIndices, [1])
        XCTAssertEqual(collection.thumbnailEntries.map(\.id), [items[1].id])
        XCTAssertEqual(collection.projectionRebuildCount, initialRebuilds + 1)
    }

    private func makeItems(count: Int) -> [ImageCollection.Item] {
        (0..<count).map { index in
            let id = PhotoAssetID.imported(UUID())
            let source = PhotoAssetSource(
                data: Data([UInt8(index & 0xff)]),
                id: id,
                fingerprint: PhotoSourceFingerprint(
                    byteCount: 1,
                    modificationDate: nil,
                    resourceIdentifier: id.raw,
                    sampleDigest: id.raw
                )
            )
            return ImageCollection.Item(asset: PhotoAsset(
                source: source,
                filename: "photo-\(index).jpg",
                fileType: "jpg"
            ))
        }
    }
}
