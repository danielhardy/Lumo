import XCTest
@testable import LumoKit

@MainActor
final class OpenImageDialogTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                return XCTFail("timed out waiting for \(description)")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testOpenImagesAddsSortedURLBackedAssetsAndLoadsTheFirst() async throws {
        let later = try Fixtures.writeGradientPNG(
            width: 24, height: 16, named: "later.png", in: tempDirectory
        )
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 24, named: "first.png", in: tempDirectory
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.openImages(urls: [later, first])

        XCTAssertEqual(viewModel.collection.items.map(\.url), [
            first.standardizedFileURL, later.standardizedFileURL
        ])
        XCTAssertTrue(viewModel.collection.items.allSatisfy { $0.imageData == nil })
        XCTAssertTrue(viewModel.navigation.isEdit)
        try await waitUntil("the first selected image") {
            viewModel.sourceName == first.lastPathComponent && viewModel.sourceImage != nil
        }
    }

    func testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs() async throws {
        let image = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "single.png", in: tempDirectory
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.openImages(urls: [image, image])

        XCTAssertEqual(viewModel.collection.items.count, 1)
        XCTAssertEqual(viewModel.collection.items.first?.url, image.standardizedFileURL)
        XCTAssertTrue(viewModel.navigation.isEdit)
        try await waitUntil("the single image") {
            viewModel.sourceName == image.lastPathComponent && viewModel.sourceImage != nil
        }
    }

    func testEmptyOpenResultLeavesCurrentCollectionAndEditUntouched() async throws {
        let image = try Fixtures.writeGradientPNG(
            width: 20, height: 12, named: "existing.png", in: tempDirectory
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.openImages(urls: [image])
        try await waitUntil("the existing image") { viewModel.sourceImage != nil }

        let existingIDs = viewModel.collection.items.map(\.id)
        let existingSource = viewModel.sourceName
        viewModel.openImages(urls: [])

        XCTAssertEqual(viewModel.collection.items.map(\.id), existingIDs)
        XCTAssertEqual(viewModel.sourceName, existingSource)
        XCTAssertTrue(viewModel.navigation.isEdit)
    }
}
