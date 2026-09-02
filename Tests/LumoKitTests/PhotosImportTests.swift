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
}
