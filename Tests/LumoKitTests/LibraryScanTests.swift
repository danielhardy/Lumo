import XCTest
@testable import LumoKit

/// Covers the folder scans that were moved off the main actor (B3), the error
/// surfacing that used to be dead (`scanError` was set but never displayed),
/// and the collection state that drives navigation.
@MainActor
final class LibraryScanTests: TempDirectoryTestCase {

    /// Scans are asynchronous now, so tests wait on the published state rather
    /// than reading it straight after the call.
    private func waitForScan(_ library: LUTLibrary, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while library.isScanning {
            if Date() > deadline { XCTFail("scan did not finish within \(timeout)s"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - LUTLibrary

    func testScanReturnsBeforeWorkCompletes() throws {
        let library = LUTLibrary()
        for i in 0..<3 {
            try Fixtures.writeCube(
                Fixtures.identityCubeText(size: 8), named: "lut\(i).cube", in: tempDirectory
            )
        }

        library.scan(tempDirectory)
        // The whole point of B3: the caller is not blocked on parsing.
        XCTAssertTrue(library.isScanning)
        XCTAssertTrue(library.allLUTs.isEmpty, "results should not be ready synchronously")
    }

    func testScanGroupsTopLevelAndSubfolders() async throws {
        let library = LUTLibrary()
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "root1.cube", in: tempDirectory)
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "root2.cube", in: tempDirectory)

        let leica = tempDirectory.appendingPathComponent("Leica")
        try FileManager.default.createDirectory(at: leica, withIntermediateDirectories: true)
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "LEICA VIV.cube", in: leica)

        library.scan(tempDirectory)
        try await waitForScan(library)

        XCTAssertNil(library.scanError)
        XCTAssertEqual(library.allLUTs.count, 3)
        XCTAssertEqual(library.categories.map(\.name), ["General", "Leica"])
        XCTAssertEqual(library.categories.first { $0.name == "General" }?.luts.count, 2)
        XCTAssertEqual(library.categories.first { $0.name == "Leica" }?.luts.count, 1)
    }

    func testScanSkipsUnparseableFilesButKeepsTheRest() async throws {
        let library = LUTLibrary()
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "good.cube", in: tempDirectory)
        try Fixtures.writeCube("this is not a cube", named: "bad.cube", in: tempDirectory)

        library.scan(tempDirectory)
        try await waitForScan(library)

        XCTAssertEqual(library.allLUTs.count, 1, "a malformed file should not sink the whole folder")
        XCTAssertEqual(library.allLUTs.first?.name, "good")
        XCTAssertNil(library.scanError)
    }

    func testScanIgnoresNonCubeFiles() async throws {
        let library = LUTLibrary()
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "real.cube", in: tempDirectory)
        try "hello".write(to: tempDirectory.appendingPathComponent("notes.txt"),
                          atomically: true, encoding: .utf8)
        try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "photo.jpg", in: tempDirectory)

        library.scan(tempDirectory)
        try await waitForScan(library)

        XCTAssertEqual(library.allLUTs.count, 1)
    }

    /// A missing folder is the likeliest failure, since the folder is restored
    /// from a bookmark every launch. `FileManager.enumerator(at:)` hands back a
    /// live-but-empty enumerator for one, so a nil check alone reported "no
    /// LUTs" for what was really a missing directory.
    func testMissingFolderIsReportedAsMissingNotEmpty() async throws {
        let library = LUTLibrary()
        library.scan(tempDirectory.appendingPathComponent("does-not-exist"))
        try await waitForScan(library)

        let error = try XCTUnwrap(library.scanError, "a missing folder must be reported, not silent")
        XCTAssertTrue(error.contains("does-not-exist"), "the message should name the folder: \(error)")
        // The distinction matters to the user: "add some LUTs" and "your folder
        // moved" call for different actions, and a bare non-nil check can't tell
        // them apart because the empty-folder message also names the folder.
        XCTAssertTrue(error.contains("Can't find"),
                      "a missing folder should not be reported as merely empty: \(error)")
        XCTAssertFalse(error.contains("No .cube files"), error)
        XCTAssertTrue(library.allLUTs.isEmpty)
    }

    func testEmptyFolderIsReportedAsEmpty() async throws {
        let library = LUTLibrary()
        library.scan(tempDirectory)
        try await waitForScan(library)

        let error = try XCTUnwrap(library.scanError, "an empty folder should say so")
        XCTAssertTrue(error.contains("No .cube files"), error)
        XCTAssertFalse(error.contains("Can't find"), error)
    }

    func testRescanReplacesPreviousResults() async throws {
        let library = LUTLibrary()
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "first.cube", in: tempDirectory)
        library.scan(tempDirectory)
        try await waitForScan(library)
        XCTAssertEqual(library.allLUTs.count, 1)

        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "second.cube", in: tempDirectory)
        library.scan(tempDirectory)
        try await waitForScan(library)
        XCTAssertEqual(library.allLUTs.count, 2, "a rescan should pick up new files")

        // And a failed rescan clears stale results rather than leaving them up.
        library.scan(tempDirectory.appendingPathComponent("gone"))
        try await waitForScan(library)
        XCTAssertTrue(library.allLUTs.isEmpty)
        XCTAssertNotNil(library.scanError)
    }

    // MARK: - ImageCollection

    func testCollectionScansFolderAndRecordsSubfolders() async throws {
        let collection = ImageCollection()
        try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "b.jpg", in: tempDirectory)
        try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "a.jpg", in: tempDirectory)

        let nested = tempDirectory.appendingPathComponent("Trip")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "c.jpg", in: nested)

        collection.loadFromFolder(tempDirectory)
        XCTAssertTrue(collection.items.isEmpty, "scan should not block the caller")
        await collection.scanCompletion()

        XCTAssertEqual(collection.items.count, 3)
        XCTAssertTrue(collection.isActive)
        // Top level first (empty subfolder sorts before "Trip"), then by name.
        XCTAssertEqual(collection.items.map(\.displayName), ["a", "b", "c"])
        XCTAssertEqual(collection.items.map(\.subfolder), ["", "", "Trip"])
    }

    func testLargeScanPublishesAFirstBatchBeforeTheTraversalFinishes() async throws {
        for index in 0..<96 {
            try Fixtures.writeJPEG(
                width: 8, height: 8, orientation: 1,
                named: String(format: "photo-%03d.jpg", index), in: tempDirectory
            )
        }

        let collection = ImageCollection()
        collection.loadFromFolder(tempDirectory)

        var sawPartialScan = false
        let deadline = Date().addingTimeInterval(5)
        while collection.isScanning {
            if !collection.items.isEmpty && collection.items.count < 96 {
                sawPartialScan = true
                break
            }
            if Date() > deadline { break }
            await Task.yield()
        }
        XCTAssertTrue(sawPartialScan, "a large folder should publish rows before traversal completes")

        await collection.scanCompletion()
        XCTAssertEqual(collection.items.count, 96)
        XCTAssertEqual(collection.items.map(\.displayName),
                       (0..<96).map { String(format: "photo-%03d", $0) })
    }

    func testSwitchingFoldersCannotPublishResultsFromTheCancelledScan() async throws {
        let first = tempDirectory.appendingPathComponent("first")
        let second = tempDirectory.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        for index in 0..<96 {
            try Fixtures.writeJPEG(
                width: 8, height: 8, orientation: 1,
                named: "old-\(index).jpg", in: first
            )
        }
        try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "current.jpg", in: second)

        let collection = ImageCollection()
        collection.loadFromFolder(first)
        collection.loadFromFolder(second)
        await collection.scanCompletion()
        await collection.metadataCompletion()

        XCTAssertEqual(collection.items.map(\.displayName), ["current"])
        XCTAssertTrue(collection.items.allSatisfy {
            $0.url?.deletingLastPathComponent().standardizedFileURL == second.standardizedFileURL
        })
        XCTAssertFalse(collection.isScanning)
    }

    func testMetadataLoadsAfterDiscoveryWithoutBlockingTheFirstRows() async throws {
        let url = try Fixtures.writeJPEG(
            named: "camera.jpg",
            in: tempDirectory,
            exif: [kCGImagePropertyExifISOSpeedRatings: [400]],
            tiff: [kCGImagePropertyTIFFMake: "Lumo", kCGImagePropertyTIFFModel: "Test Body"]
        )

        let collection = ImageCollection()
        collection.loadFromFolder(tempDirectory)

        // Discovery publishes the item before the deferred ImageIO metadata read completes.
        let deadline = Date().addingTimeInterval(5)
        while collection.items.isEmpty {
            if Date() > deadline { XCTFail("discovery did not publish an item"); return }
            await Task.yield()
        }
        XCTAssertNil(collection.items.first?.metadata)

        await collection.scanCompletion()
        await collection.metadataCompletion()
        let metadata = try XCTUnwrap(collection.items.first?.metadata)
        XCTAssertEqual(metadata.make, "Lumo")
        XCTAssertEqual(metadata.model, "Test Body")
        XCTAssertEqual(metadata.iso, "ISO 400")
        XCTAssertEqual(metadata.pixelWidth, 64)
        XCTAssertEqual(metadata.pixelHeight, 48)
        XCTAssertEqual(collection.items.first?.url?.standardizedFileURL, url.standardizedFileURL)
    }

    func testUnreadableImageIsReportedWithoutDiscardingReadableFiles() async throws {
        try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "good.jpg", in: tempDirectory)
        try Data("not an image".utf8).write(to: tempDirectory.appendingPathComponent("bad.jpg"))

        let collection = ImageCollection()
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()
        await collection.metadataCompletion()

        XCTAssertEqual(collection.items.map(\.displayName), ["good"])
        XCTAssertTrue(collection.scanWarnings.contains { $0.message.contains("bad.jpg") })
    }

    /// Regression: dropping the currently-active item (an unreadable file discovered during
    /// metadata scan, here alphabetically first and so the initial active selection) must not
    /// leave the library with a non-empty item list and no active selection.
    func testRemovingActiveItemFallsBackToRemainingSelection() async throws {
        try Data("not an image".utf8).write(to: tempDirectory.appendingPathComponent("aaa-bad.jpg"))
        try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "zzz-good.jpg", in: tempDirectory)

        let collection = ImageCollection()
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()
        await collection.metadataCompletion()

        XCTAssertEqual(collection.items.map(\.displayName), ["zzz-good"])
        XCTAssertNotNil(collection.selectedItem, "a non-empty library must keep an active item")
        XCTAssertEqual(collection.selectedItem?.displayName, "zzz-good")
    }

    /// Regression for B13: a folder holding exactly one image used to leave
    /// `isActive` false, which killed ←/→ and `selectedItem` while the browser
    /// still listed the row.
    func testSingleImageFolderIsActive() async throws {
        let collection = ImageCollection()
        try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "only.jpg", in: tempDirectory)

        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()

        XCTAssertEqual(collection.items.count, 1)
        XCTAssertTrue(collection.isActive, "one image is still a browsable set")
        XCTAssertNotNil(collection.selectedItem)
    }

    func testEmptyFolderIsNotActive() async throws {
        let collection = ImageCollection()
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()

        XCTAssertTrue(collection.items.isEmpty)
        XCTAssertFalse(collection.isActive)
        XCTAssertNil(collection.selectedItem)
    }

    func testCollectionIgnoresUnsupportedFiles() async throws {
        let collection = ImageCollection()
        try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "keep.jpg", in: tempDirectory)
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "skip.cube", in: tempDirectory)
        try "x".write(to: tempDirectory.appendingPathComponent("skip.txt"), atomically: true, encoding: .utf8)

        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()

        XCTAssertEqual(collection.items.map(\.displayName), ["keep"])
    }

    func testNavigationStaysInBounds() async throws {
        let collection = ImageCollection()
        for name in ["a", "b", "c"] {
            try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "\(name).jpg", in: tempDirectory)
        }
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()

        XCTAssertEqual(collection.selectedIndex, 0)
        collection.selectPrevious()
        XCTAssertEqual(collection.selectedIndex, 0, "should not step before the first image")

        collection.selectNext()
        collection.selectNext()
        XCTAssertEqual(collection.selectedIndex, 2)
        collection.selectNext()
        XCTAssertEqual(collection.selectedIndex, 2, "should not step past the last image")
    }

    func testClearDropsBrowsingStateButKeepsNothingStale() async throws {
        let collection = ImageCollection()
        try Fixtures.writeJPEG(width: 8, height: 8, orientation: 1, named: "a.jpg", in: tempDirectory)
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()
        XCTAssertFalse(collection.items.isEmpty)

        collection.clear()
        XCTAssertTrue(collection.items.isEmpty)
        XCTAssertFalse(collection.isActive)
        XCTAssertNil(collection.sourceFolderURL)
        XCTAssertNil(collection.selectedItem)
    }
}
