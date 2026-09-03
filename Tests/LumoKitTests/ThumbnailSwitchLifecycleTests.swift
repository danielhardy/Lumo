import XCTest
@testable import LumoKit

@MainActor
final class ThumbnailSwitchLifecycleTests: TempDirectoryTestCase {

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

    private func loadCollection(
        _ viewModel: AppViewModel,
        first: URL,
        second: URL
    ) async throws {
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        XCTAssertEqual(viewModel.collection.items.map(\.url), [first, second])
    }

    func testFilmstripSelectionPresentsRepeatedSelectionAndSettlesHistogram() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = AppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the first presented photo") {
            viewModel.sourceURL == first && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }

        viewModel.isInspectorPresented = true
        try await waitUntil("the first histogram") { viewModel.histogram != nil }

        viewModel.selectCollectionImage(at: 1)
        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the repeated second selection") {
            viewModel.sourceURL == second && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
                && viewModel.histogram != nil
        }

        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[1].id)
        XCTAssertEqual(viewModel.histogramErrorMessage, nil)
        XCTAssertFalse(viewModel.isHistogramLoading)
        let requests = await engine.histogramRequests
        XCTAssertTrue(requests.last?.source?.backing == .url(second))
    }

    func testSequentialOpenPresentsReplacementWithoutAnotherUserAction() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "sequential-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "sequential-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = AppViewModel(engine: engine)

        viewModel.openImage(url: first)
        try await waitUntil("the first preview") {
            viewModel.sourceURL == first && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }

        // Keep the replacement renderer in flight. The test releases only B and never performs a
        // second model/view action after that release, matching the reported spinner failure.
        await engine.gatePreviews()
        viewModel.openImage(url: second)
        try await waitUntil("the second preview request") {
            let requests = await engine.previewRequests
            return viewModel.sourceURL == second
                && requests.contains { $0.source?.backing == .url(second) }
        }
        XCTAssertEqual(viewModel.previewState, .loading)
        XCTAssertFalse(viewModel.isLoading, "source preparation is complete while B renders")

        await engine.releaseNextPreview()
        try await waitUntil("the second preview") {
            viewModel.sourceURL == second && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }
        XCTAssertFalse(viewModel.isLoading)
    }

    func testRapidThumbnailChangesCannotPublishAnObsoleteSourceOrHistogram() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        await engine.gateSourcePreparation()
        let viewModel = AppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the first source preparation") {
            await engine.sourcePreparationCount == 1
        }
        viewModel.selectCollectionImage(at: 1)
        await engine.releaseSourcePreparation()

        try await waitUntil("the latest photo presentation") {
            viewModel.sourceURL == second && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }
        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[1].id)
        XCTAssertNotEqual(viewModel.sourceURL, first)

        await engine.gateHistogram()
        viewModel.isInspectorPresented = true
        try await waitUntil("the current histogram request") {
            await engine.histogramRequests.contains { $0.source?.backing == .url(second) }
        }
        viewModel.selectCollectionImage(at: 0)
        await engine.releaseHistograms()

        try await waitUntil("the first photo after the switch back") {
            viewModel.sourceURL == first && viewModel.previewState == .ready
                && viewModel.histogram != nil
        }
        let histogramRequests = await engine.histogramRequests
        XCTAssertTrue(histogramRequests.last?.source?.backing == .url(first))
    }

    func testLibraryGridHandoffPresentsTheSelectedPhotoWithoutTabSwitching() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await loadCollection(viewModel, first: first, second: second)

        XCTAssertTrue(viewModel.navigate(to: .grid))
        viewModel.selectLibraryItem(at: 1)
        XCTAssertTrue(viewModel.navigate(to: .edit))

        try await waitUntil("the selected grid photo and histogram") {
            viewModel.collection.selection.activeID == viewModel.collection.items[1].id
                && viewModel.sourceURL == second
                && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }
        XCTAssertNil(viewModel.histogramErrorMessage)
        XCTAssertFalse(viewModel.isHistogramLoading)
    }

    func testFailedSourceAndFailedHistogramLeaveTerminalStates() async throws {
        let missing = tempDirectory.appendingPathComponent("missing.png")
        let sourceEngine = FakeRenderEngine()
        let sourceViewModel = AppViewModel(engine: sourceEngine)
        sourceViewModel.openImage(url: missing)

        try await waitUntil("the source failure") {
            sourceViewModel.previewState == .failed && !sourceViewModel.isLoading
        }
        XCTAssertNil(sourceViewModel.sourceImage)
        XCTAssertNotNil(sourceViewModel.errorMessage)

        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "histogram-failure.png", in: tempDirectory
        )
        let histogramEngine = FakeRenderEngine()
        await histogramEngine.setShouldFailHistogram(true)
        let histogramViewModel = AppViewModel(engine: histogramEngine)
        histogramViewModel.openImage(url: image)
        try await waitUntil("the image presentation") {
            histogramViewModel.previewState == .ready
        }
        histogramViewModel.isInspectorPresented = true
        try await waitUntil("the histogram failure") {
            !histogramViewModel.isHistogramLoading
                && histogramViewModel.histogramErrorMessage != nil
        }
        XCTAssertNil(histogramViewModel.histogram)
    }
}
