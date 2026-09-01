import XCTest
@testable import LumoKit

final class NavigationStateTests: XCTestCase {
    func testModeIsAnExplicitSmallValueState() {
        var state = NavigationState()

        XCTAssertEqual(state.mode, .edit)
        XCTAssertTrue(state.isEdit)
        XCTAssertFalse(state.isGrid)

        state.move(to: .grid)
        XCTAssertEqual(state.mode, .grid)
        XCTAssertTrue(state.isGrid)
        XCTAssertEqual(state.mode.shortcut, "G")

        state.move(to: .edit)
        XCTAssertEqual(state.mode.title, "Edit")
    }
}

@MainActor
final class WorkspaceNavigationTests: TempDirectoryTestCase {
    func testGridSelectionHandsTheActivePhotoToEdit() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()

        XCTAssertEqual(viewModel.collection.items.map(\.url), [first, second])
        XCTAssertTrue(viewModel.navigate(to: .grid))
        XCTAssertEqual(viewModel.navigation.mode, .grid)

        viewModel.selectLibraryItem(at: 1)
        let selected = try XCTUnwrap(viewModel.collection.selectedItem)
        XCTAssertEqual(selected.url, second)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        XCTAssertEqual(viewModel.navigation.mode, .edit)

        let deadline = Date().addingTimeInterval(5)
        while viewModel.sourceURL != second {
            if Date() > deadline {
                return XCTFail("the selected grid photo was not handed to the editor")
            }
            await Task.yield()
        }
    }

    func testGridAndEditNavigationRejectsAnUnavailableCollection() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        XCTAssertFalse(viewModel.navigate(to: .grid))
        XCTAssertEqual(viewModel.navigation.mode, .edit)
        XCTAssertFalse(viewModel.navigate(to: .edit))
    }

    func testSourceToolbarActionLeavesGridAndRevealsTheEditorSidebar() async throws {
        try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "photo.png", in: tempDirectory
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        XCTAssertTrue(viewModel.navigate(to: .grid))

        viewModel.toggleSourceBrowser()

        XCTAssertEqual(viewModel.navigation.mode, .edit)
        XCTAssertTrue(viewModel.isSourceBrowserPresented)
    }
}
