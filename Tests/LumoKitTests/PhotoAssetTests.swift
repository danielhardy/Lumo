import Foundation
import XCTest
@testable import LumoKit

final class PhotoAssetTests: TempDirectoryTestCase {

    func testUnchangedFileHasStableIdentityAndFingerprintAcrossRebuilds() throws {
        let url = tempDirectory.appendingPathComponent("same.jpg")
        try Data("unchanged photo".utf8).write(to: url)

        let first = PhotoAsset.discoveredFile(at: url)
        let second = PhotoAsset.discoveredFile(at: url)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.source.fingerprint, second.source.fingerprint)
        XCTAssertEqual(first.cacheKey, second.cacheKey)
    }

    func testDifferentFilesDoNotCollideEvenWhenTheirBytesMatch() throws {
        let bytes = Data("the same pixels".utf8)
        let firstURL = tempDirectory.appendingPathComponent("first.jpg")
        let secondURL = tempDirectory.appendingPathComponent("second.jpg")
        try bytes.write(to: firstURL)
        try bytes.write(to: secondURL)

        XCTAssertNotEqual(PhotoAssetID.file(firstURL), PhotoAssetID.file(secondURL))

        // Data-only Photos imports intentionally use content identity. A provider with two
        // distinct Photos assets should pass their durable local identifiers instead.
        XCTAssertEqual(PhotoAssetID.data(bytes), PhotoAssetID.data(bytes))
        XCTAssertNotEqual(
            PhotoAssetID.photos(localIdentifier: "A"),
            PhotoAssetID.photos(localIdentifier: "B")
        )
    }

    func testChangingAFileChangesItsCacheIdentity() throws {
        let url = tempDirectory.appendingPathComponent("replace.jpg")
        try Data(repeating: 0x10, count: 512).write(to: url)
        let before = PhotoAsset.discoveredFile(at: url)

        try Data(repeating: 0xE0, count: 512).write(to: url)
        let after = PhotoAsset.discoveredFile(at: url)

        // The logical file identity may remain the same for an in-place edit. The source signature
        // must not, so a render/thumbnail cache cannot silently serve the old bytes.
        XCTAssertNotEqual(before.source.fingerprint, after.source.fingerprint)
        XCTAssertFalse(before.source.matches(after.source))
        XCTAssertNotEqual(before.cacheKey, after.cacheKey)
    }

    func testMovingAnUnchangedFileRetainsTheSourceFingerprint() throws {
        let originalURL = tempDirectory.appendingPathComponent("before.jpg")
        let movedURL = tempDirectory.appendingPathComponent("after.jpg")
        try Data(repeating: 0x44, count: 512).write(to: originalURL)
        let before = PhotoAsset.discoveredFile(at: originalURL)

        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        let after = PhotoAsset.discoveredFile(at: movedURL)

        XCTAssertTrue(before.source.matches(after.source), "a move should be relinkable by its source fingerprint")
        XCTAssertEqual(before.source.fingerprint.sampleDigest, after.source.fingerprint.sampleDigest)
    }

    func testAssetAndMutableLibraryStateRoundTripThroughCodable() throws {
        let source = PhotoAssetSource(data: Data("photo".utf8))
        let asset = PhotoAsset(
            source: source,
            filename: "photo.jpg",
            fileType: "JPG",
            metadata: PhotoAssetMetadata(
                dimensions: PhotoPixelDimensions(width: 4000, height: 3000),
                captureDate: "Aug 31, 2026 at 10:00 AM",
                cameraMake: "Lumo",
                cameraModel: "Prototype",
                lens: "35mm"
            ),
            libraryState: PhotoAssetLibraryState(
                rating: 4,
                flag: .pick,
                thumbnail: .ready
            )
        )

        let encoded = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(PhotoAsset.self, from: encoded)

        XCTAssertEqual(decoded, asset)
        XCTAssertEqual(decoded.libraryState.rating, 4)
        XCTAssertEqual(decoded.libraryState.flag, .pick)
        XCTAssertEqual(decoded.metadata.dimensions?.width, 4000)
        XCTAssertEqual(decoded.metadata.camera, "Lumo Prototype")
    }

    @MainActor
    func testCollectionItemsUseStableAssetIDs() async throws {
        let url = try Fixtures.writeJPEG(
            width: 20, height: 10, orientation: 1, named: "photo.jpg", in: tempDirectory
        )
        let collection = ImageCollection()
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()
        let firstID = try XCTUnwrap(collection.items.first?.id)

        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()

        XCTAssertEqual(collection.items.first?.id, firstID)
        XCTAssertEqual(collection.items.first?.url, url.standardizedFileURL)
        XCTAssertEqual(collection.items.first?.asset.fileType, "jpg")
        XCTAssertEqual(collection.items.first?.asset.metadata.dimensions?.width, 20)
    }
}
