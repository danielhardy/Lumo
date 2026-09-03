import XCTest
@testable import LumoKit

@MainActor
final class PhotosImportTests: TempDirectoryTestCase {

    func testStreamingImportRetainsFullBytesAndUsesPhotosIdentity() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "portrait.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let collection = ImageCollection()

        collection.beginDataImport()
        let item = ImageCollection.PhotoImportItem(
            name: "Portrait", data: data, localIdentifier: "photos.local.portrait"
        )
        let id = collection.appendDataImport(item, ordinal: 0)
        collection.finishDataImport()

        XCTAssertEqual(id, .photos(localIdentifier: "photos.local.portrait"))
        XCTAssertEqual(collection.items.count, 1)
        XCTAssertEqual(collection.items[0].imageData, data,
                       "the collection must retain the original payload, not a preview")
        XCTAssertEqual(collection.items[0].asset.source.id, id)
    }

    func testImportReservationsReplaceByOrdinalWithoutReordering() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "reserved.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 3)
        XCTAssertEqual(viewModel.collection.pendingImportSlots.count, 3)
        XCTAssertEqual(viewModel.collection.thumbnailEntries.count, 3)
        XCTAssertTrue(viewModel.collection.thumbnailEntries.allSatisfy(\.isPlaceholder))

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Third", data: data, localIdentifier: "third"),
            ordinal: 2
        )
        var entries = viewModel.collection.thumbnailEntries
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].isPlaceholder)
        XCTAssertTrue(entries[1].isPlaceholder)
        XCTAssertFalse(entries[2].isPlaceholder)
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["Third"])

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "First", data: data, localIdentifier: "first"),
            ordinal: 0
        )
        entries = viewModel.collection.thumbnailEntries
        XCTAssertFalse(entries[0].isPlaceholder)
        XCTAssertTrue(entries[1].isPlaceholder)
        XCTAssertFalse(entries[2].isPlaceholder)
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["First", "Third"])
        XCTAssertEqual(entries[0].itemIndex, 0)
        XCTAssertEqual(entries[2].itemIndex, 1)
    }

    func testImportProjectionKeepsPlaceholdersButFiltersLoadedArrivals() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "filtered.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let collection = ImageCollection()

        collection.setFilter(LibraryFilter(flag: .picks, rating: .any))
        collection.beginDataImport(reservedCount: 3)
        let filteredIdentifier = "filtered-\(UUID().uuidString)"
        let filteredID = collection.appendDataImport(
            ImageCollection.PhotoImportItem(
                name: "Filtered", data: data, localIdentifier: filteredIdentifier
            ),
            ordinal: 0
        )

        var entries = collection.thumbnailEntries
        XCTAssertEqual(entries.compactMap(\.placeholder?.ordinal), [1, 2])
        XCTAssertFalse(entries.contains(where: { $0.id == filteredID }))

        let pickedID = collection.appendDataImport(
            ImageCollection.PhotoImportItem(
                name: "Picked", data: data, localIdentifier: "picked-\(UUID().uuidString)"
            ),
            ordinal: 2
        )
        XCTAssertTrue(collection.setFlag(.pick, for: pickedID))

        entries = collection.thumbnailEntries
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.compactMap(\.placeholder?.ordinal), [1])
        XCTAssertEqual(entries.last?.id, pickedID)
        XCTAssertFalse(entries.last?.isPlaceholder ?? true)

        collection.finishDataImport()
        XCTAssertEqual(collection.thumbnailEntries.map(\.id), [pickedID])
    }

    func testUnreservedImportOrdinalAppearsAsLoadedTailEntry() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "overflow.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let collection = ImageCollection()

        collection.beginDataImport(reservedCount: 2)
        let overflowID = collection.appendDataImport(
            ImageCollection.PhotoImportItem(name: "Overflow", data: data, localIdentifier: "overflow"),
            ordinal: 2
        )

        var entries = collection.thumbnailEntries
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].isPlaceholder)
        XCTAssertTrue(entries[1].isPlaceholder)
        XCTAssertEqual(entries[2].id, overflowID)
        XCTAssertEqual(entries[2].itemIndex, 0)
        XCTAssertFalse(entries[2].isPlaceholder)

        let reservedID = collection.appendDataImport(
            ImageCollection.PhotoImportItem(name: "Reserved", data: data, localIdentifier: "reserved"),
            ordinal: 1
        )
        entries = collection.thumbnailEntries
        XCTAssertEqual(entries.map(\.isPlaceholder), [true, false, false])
        XCTAssertEqual(entries[1].id, reservedID)
        XCTAssertEqual(entries[2].id, overflowID)

        collection.finishDataImport()
        XCTAssertEqual(collection.thumbnailEntries.map(\.id), [reservedID, overflowID])
    }

    func testLoadedEntryIdentitySurvivesImportCompletion() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "stable-entry.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let collection = ImageCollection()

        collection.beginDataImport(reservedCount: 2)
        let firstID = collection.appendDataImport(
            ImageCollection.PhotoImportItem(name: "First", data: data, localIdentifier: "first"),
            ordinal: 0
        )
        let loadedEntryID = try XCTUnwrap(
            collection.thumbnailEntries.first(where: { !$0.isPlaceholder })?.id
        )

        XCTAssertEqual(loadedEntryID, firstID)
        collection.finishDataImport()

        XCTAssertEqual(collection.thumbnailEntries.map(\.id), [firstID])
    }

    func testFailureAndCancellationClearReservationsWithoutCreatingTargets() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "partial.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 3)
        viewModel.recordPhotosImportFailure(name: "Unavailable", ordinal: 1)
        XCTAssertEqual(
            viewModel.collection.thumbnailEntries.compactMap(\.placeholder?.state),
            [.pending, .failed, .pending]
        )
        XCTAssertTrue(viewModel.collection.selectedItem == nil)

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Kept", data: data, localIdentifier: "kept"),
            ordinal: 0
        )
        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertTrue(viewModel.collection.pendingImportSlots.isEmpty)
        XCTAssertEqual(viewModel.collection.thumbnailEntries.count, 1)
        XCTAssertFalse(viewModel.collection.thumbnailEntries[0].isPlaceholder)

        viewModel.beginPhotosImport(totalCount: 2)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Cancelled", data: data, localIdentifier: "cancelled"),
            ordinal: 0
        )
        viewModel.finishPhotosImport(cancelled: true)
        XCTAssertTrue(viewModel.collection.pendingImportSlots.isEmpty)
        XCTAssertEqual(viewModel.collection.thumbnailEntries.count, 1)
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["Cancelled"])
    }

    func testEmptyImportHasNoReservationsOrActiveDestination() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 0)
        XCTAssertTrue(viewModel.collection.pendingImportSlots.isEmpty)
        XCTAssertTrue(viewModel.collection.thumbnailEntries.isEmpty)
        XCTAssertFalse(viewModel.collection.isActive)

        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertTrue(viewModel.collection.pendingImportSlots.isEmpty)
        XCTAssertFalse(viewModel.collection.isActive)
    }

    func testPartialImportKeepsSuccessfulItemsWhenOneItemFails() throws {
        let firstURL = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "first.jpg", in: tempDirectory
        )
        let secondURL = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "second.jpg", in: tempDirectory
        )
        let firstData = try Data(contentsOf: firstURL)
        let secondData = try Data(contentsOf: secondURL)
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 3)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(
                name: "First", data: firstData, localIdentifier: "photos.first"
            ),
            ordinal: 0
        )
        viewModel.recordPhotosImportFailure(name: "Unavailable")
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(
                name: "Second", data: secondData, localIdentifier: "photos.second"
            ),
            ordinal: 2
        )

        XCTAssertEqual(viewModel.collection.items.map(\.asset.id), [
            .photos(localIdentifier: "photos.first"),
            .photos(localIdentifier: "photos.second"),
        ])
        XCTAssertEqual(viewModel.collection.items.map(\.imageData), [firstData, secondData])
        XCTAssertEqual(viewModel.photosImportProgress?.processed, 3)
        XCTAssertEqual(viewModel.photosImportProgress?.imported, 2)
        XCTAssertEqual(viewModel.photosImportProgress?.failed, 1)

        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertNil(viewModel.photosImportProgress)
        XCTAssertTrue(viewModel.statusMessage.contains("2 imported"))
        XCTAssertTrue(viewModel.statusMessage.contains("1 skipped"))
    }

    func testCancellationLeavesAlreadyImportedOriginalsUsable() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "cancel.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 2)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(
                name: "Kept", data: data, localIdentifier: "photos.kept"
            ),
            ordinal: 0
        )
        viewModel.finishPhotosImport(cancelled: true)

        XCTAssertEqual(viewModel.collection.items.count, 1)
        XCTAssertEqual(viewModel.collection.items[0].imageData, data)
        XCTAssertTrue(viewModel.statusMessage.contains("cancelled"))
    }

    func testFirstSuccessfulImportPresentsInspectorOnceAndPreservesInspectorState() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "inspector-import.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.inspectorTab = .effects
        viewModel.metadata.make = "stale camera"
        viewModel.histogram = HistogramData(
            red: [1], green: [1], blue: [1], luma: [1]
        )

        viewModel.beginPhotosImport(totalCount: 2)
        XCTAssertFalse(viewModel.isInspectorPresented)

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "First", data: data, localIdentifier: "first"),
            ordinal: 0
        )

        XCTAssertTrue(viewModel.isInspectorPresented)
        XCTAssertEqual(viewModel.inspectorTab, .effects)
        XCTAssertTrue(viewModel.metadata.isEmpty)
        XCTAssertNil(viewModel.histogram)

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Second", data: data, localIdentifier: "second"),
            ordinal: 1
        )

        XCTAssertTrue(viewModel.isInspectorPresented)
        XCTAssertEqual(viewModel.inspectorTab, .effects)
        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[0].id)
    }

    func testFirstImportFailureThenSuccessStillPresentsInspectorForTheSuccessfulItem() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "second-succeeds.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 2)
        viewModel.recordPhotosImportFailure(name: "Unavailable", ordinal: 0)
        XCTAssertFalse(viewModel.isInspectorPresented)

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Second", data: data, localIdentifier: "second"),
            ordinal: 1
        )

        XCTAssertTrue(viewModel.isInspectorPresented)
    }

    func testPhotosImportWithoutAnAcceptedItemLeavesInspectorPresentationUnchanged() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 2)
        viewModel.recordPhotosImportFailure(name: "Unavailable", ordinal: 0)
        viewModel.recordPhotosImportFailure(name: "Unavailable", ordinal: 1)
        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertFalse(viewModel.isInspectorPresented)

        viewModel.beginPhotosImport(totalCount: 1)
        viewModel.finishPhotosImport(cancelled: true)
        XCTAssertFalse(viewModel.isInspectorPresented)

        viewModel.beginPhotosImport(totalCount: 0)
        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertFalse(viewModel.isInspectorPresented)
    }

    func testRepeatedPhotosImportsDoNotReopenOrChangeInspectorTab() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "repeated-import.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.inspectorTab = .look

        viewModel.beginPhotosImport(totalCount: 1)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "First", data: data, localIdentifier: "first"),
            ordinal: 0
        )
        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertTrue(viewModel.isInspectorPresented)
        XCTAssertEqual(viewModel.inspectorTab, .look)

        viewModel.beginPhotosImport(totalCount: 1)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Second", data: data, localIdentifier: "second"),
            ordinal: 0
        )

        XCTAssertTrue(viewModel.isInspectorPresented)
        XCTAssertEqual(viewModel.inspectorTab, .look)
    }
}
