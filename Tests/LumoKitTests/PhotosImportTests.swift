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
