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

    func testReturningToEditKeepsTheWholeSelectionAndUsesTheActiveID() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )

        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        XCTAssertTrue(viewModel.navigate(to: .grid))

        viewModel.selectLibraryItem(at: 0)
        viewModel.selectLibraryItem(at: 1, modifiers: [.command])
        let selectedIDs = viewModel.collection.selection.selectedIDs
        XCTAssertEqual(selectedIDs.count, 2)
        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[1].id)

        XCTAssertTrue(viewModel.navigate(to: .edit))
        try await waitUntil("the active selected photo") {
            viewModel.sourceURL == second && viewModel.previewSurface.image != nil
        }
        XCTAssertEqual(viewModel.collection.selection.selectedIDs, selectedIDs)

        viewModel.setCanvasZoom(2)
        XCTAssertTrue(viewModel.navigate(to: .grid))
        XCTAssertTrue(viewModel.navigate(to: .edit))
        try await waitUntil("the active photo after repeated navigation") {
            viewModel.sourceURL == second && viewModel.previewSurface.image != nil
        }
        XCTAssertEqual(viewModel.collection.selection.selectedIDs, selectedIDs)
        XCTAssertEqual(viewModel.sourceURL, second)
        XCTAssertEqual(viewModel.canvasNavigation.zoom, 2)
        XCTAssertNotEqual(first, second)
    }

    func testReturningToEditReusesPreparedSourceButRepublishesMissingPreview() async throws {
        try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "photo.png", in: tempDirectory
        )

        let engine = FakeRenderEngine()
        let viewModel = AppViewModel(engine: engine)
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        XCTAssertTrue(viewModel.navigate(to: .grid))
        XCTAssertTrue(viewModel.navigate(to: .edit))
        try await waitUntil("the initial preview") {
            viewModel.sourceImage != nil && viewModel.previewSurface.image != nil
        }

        let preparationsBeforeReturn = await engine.sourcePreparationCount
        let source = try XCTUnwrap(viewModel.sourceURL)
        XCTAssertTrue(viewModel.navigate(to: .grid))
        viewModel.previewSurface.clear()
        XCTAssertTrue(viewModel.navigate(to: .edit))

        try await waitUntil("the republished preview") {
            viewModel.sourceURL == source && viewModel.previewSurface.image != nil
        }
        let preparationsAfterReturn = await engine.sourcePreparationCount
        XCTAssertEqual(preparationsAfterReturn, preparationsBeforeReturn)
        XCTAssertEqual(viewModel.collection.selection.selectedIDs.count, 1)
    }

    func testAStalePreparationCannotReplaceTheNewlyActiveLibrarySelection() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )

        let engine = FakeRenderEngine()
        await engine.gateSourcePreparation()
        let viewModel = AppViewModel(engine: engine)
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        XCTAssertTrue(viewModel.navigate(to: .grid))
        viewModel.selectLibraryItem(at: 0)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        try await waitUntil("the first preparation") {
            await engine.sourcePreparationCount == 1
        }

        XCTAssertTrue(viewModel.navigate(to: .grid))
        viewModel.selectLibraryItem(at: 1)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        await engine.releaseSourcePreparation()

        try await waitUntil("the latest selected source") {
            viewModel.sourceURL == second && viewModel.previewSurface.image != nil
        }
        XCTAssertEqual(viewModel.sourceURL, second)
        XCTAssertNotEqual(viewModel.sourceURL, first)
        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[1].id)
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(5))
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
