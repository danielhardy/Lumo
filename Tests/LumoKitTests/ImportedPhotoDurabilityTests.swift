import Foundation
import XCTest
@testable import LumoKit

@MainActor
final class ImportedPhotoDurabilityTests: TempDirectoryTestCase {

    func testURLImportsAppendCopyAndDeduplicate() throws {
        let sourceFolder = try Fixtures.makeTempDirectory("LumoImportSource")
        let libraryFolder = try Fixtures.makeTempDirectory("LumoImportLibrary")
        let first = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "first.png", in: sourceFolder
        )
        let second = try Fixtures.writeGradientPNG(
            width: 12, height: 20, named: "second.png", in: sourceFolder
        )
        let originalFirst = try Data(contentsOf: first)
        let defaults = UserDefaults(suiteName: "LumoImportedPhotoDurability-\(UUID().uuidString)")!
        let collection = ImageCollection(defaults: defaults, libraryFolderURL: libraryFolder)

        XCTAssertEqual(collection.addFromURLs([first]).count, 1)
        XCTAssertEqual(collection.addFromURLs([second]).count, 1)
        XCTAssertEqual(collection.items.count, 2)
        XCTAssertEqual(collection.addFromURLs([first]).count, 1)
        XCTAssertEqual(collection.items.count, 2)
        XCTAssertEqual(try Data(contentsOf: first), originalFirst)
        XCTAssertEqual(
            collection.items.filter { $0.url?.path.hasPrefix(libraryFolder.path + "/") == true }.count,
            2
        )
    }

    func testImportedCopyIsFoundAfterCollectionRebuild() async throws {
        let libraryFolder = try Fixtures.makeTempDirectory("LumoImportLibrary")
        let source = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "relaunch.png", in: tempDirectory
        )
        let defaults = UserDefaults(suiteName: "LumoImportedPhotoDurability-\(UUID().uuidString)")!
        let first = ImageCollection(defaults: defaults, libraryFolderURL: libraryFolder)
        _ = first.addFromURLs([source])

        let relaunched = ImageCollection(defaults: defaults, libraryFolderURL: libraryFolder)
        XCTAssertTrue(relaunched.restoreLibrary())
        await relaunched.scanCompletion()

        XCTAssertEqual(relaunched.items.count, 1)
        XCTAssertEqual(relaunched.items[0].displayName, "relaunch")
        XCTAssertEqual(
            relaunched.items[0].url?.deletingLastPathComponent().standardizedFileURL,
            libraryFolder.standardizedFileURL
        )
    }

    func testEditsFollowImportedCopyAcrossRelaunch() async throws {
        let libraryFolder = try Fixtures.makeTempDirectory("LumoImportLibrary")
        let editStoreURL = tempDirectory.appendingPathComponent("edit-records.json")
        let defaults = UserDefaults(suiteName: "LumoImportedPhotoDurability-\(UUID().uuidString)")!
        let source = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "edited.png", in: tempDirectory
        )
        let first = AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(fileURL: editStoreURL),
            preferences: defaults,
            libraryFolderURL: libraryFolder
        )
        first.openImage(url: source)
        let firstDeadline = Date().addingTimeInterval(2)
        while first.sourceImage == nil && Date() < firstDeadline {
            await Task.yield()
        }
        first.updateDocument { $0.adjustments = [.exposure(ev: 0.8)] }
        _ = await first.flushPendingWrites()

        let relaunched = AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(fileURL: editStoreURL),
            preferences: defaults,
            libraryFolderURL: libraryFolder
        )
        await relaunched.collection.scanCompletion()
        XCTAssertEqual(relaunched.collection.items.count, 1)
        relaunched.openActiveCollectionImage()

        let deadline = Date().addingTimeInterval(2)
        while relaunched.document.adjustments.isEmpty && Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(relaunched.document.adjustments, [.exposure(ev: 0.8)])
    }

    func testDataImportsRemainSelectableAfterAnIncrementalAppend() throws {
        let libraryFolder = try Fixtures.makeTempDirectory("LumoImportLibrary")
        let firstURL = try Fixtures.writeGradientPNG(width: 12, height: 8, named: "one.png", in: tempDirectory)
        let secondURL = try Fixtures.writeGradientPNG(width: 12, height: 8, named: "two.png", in: tempDirectory)
        let defaults = UserDefaults(suiteName: "LumoImportedPhotoDurability-\(UUID().uuidString)")!
        let viewModel = AppViewModel(
            engine: FakeRenderEngine(), preferences: defaults, libraryFolderURL: libraryFolder
        )
        viewModel.importPhotosData([
            (name: "one.png", data: try Data(contentsOf: firstURL)),
            (name: "two.png", data: try Data(contentsOf: secondURL))
        ])

        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["one.png", "two.png"])
        viewModel.collection.setSelection(at: 1)
        viewModel.collection.setSelection(at: 0, additive: true)
        XCTAssertEqual(viewModel.collection.selectedIndices, [0, 1])
    }
}
