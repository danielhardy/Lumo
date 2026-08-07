import XCTest
import CoreImage
@testable import LUTzyKit

/// Phase 2 Step 10b. The ship gate is "the inspector drives live re-render", which is a claim about
/// wiring, so this drives `FakeRenderEngine` and asserts on the requests it recorded. The pure-value
/// half of the step is in `AdjustmentControlTests`.
@MainActor
final class AdjustInspectorTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func openStandardImage(_ viewModel: AppViewModel) async throws {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "shot.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
    }

    // MARK: - Reading

    /// An untouched panel reads its neutrals and writes nothing. The document must still be empty.
    func testAnUntouchedPanelLeavesTheDocumentEmpty() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        for control in AdjustmentControl.allCases {
            _ = viewModel.adjustmentValue(for: control)
        }
        XCTAssertEqual(viewModel.document.adjustments, [], "reading must never write")
        XCTAssertFalse(viewModel.hasAdjustments)
    }

    /// The value a control reads is in **slider space** — mapped, not the raw stored value.
    func testTemperatureReadsBackInSliderSpace() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .temperature).wrappedValue = 9000

        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), 9000, accuracy: 1e-9,
                       "what the slider was set to is what it must read back")
        XCTAssertEqual(AdjustmentControl.temperature.value(in: viewModel.document.adjustments),
                       4000, accuracy: 1e-9,
                       "the node stores the reflected value, not the slider's")
    }

    // MARK: - Writing drives a render

    /// **The ship gate.** A slider write must reach the engine.
    func testAnAdjustmentEditRendersThroughTheEngine() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5

        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 1.5)],
                       "the document updates immediately, even though the render is debounced")

        try await waitUntil("the adjusted render") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 1.5)] }
        }
    }

    /// Resets are undebounced, per `updateDocument(debounced:)`'s contract — a button that lagged
    /// 60 ms would feel broken.
    func testResettingOneControlPreservesTheOthers() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .contrast).wrappedValue = 1.4
        viewModel.adjustmentBinding(for: .saturation).wrappedValue = 0.5
        viewModel.resetAdjustment(.contrast)

        XCTAssertEqual(viewModel.adjustmentValue(for: .contrast),
                       AdjustmentControl.contrast.neutral, accuracy: 1e-12)
        XCTAssertEqual(viewModel.adjustmentValue(for: .saturation), 0.5, accuracy: 1e-12)
    }

    func testResetAllEmptiesTheArray() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        viewModel.adjustmentBinding(for: .vibrance).wrappedValue = 0.4
        XCTAssertTrue(viewModel.hasAdjustments)

        viewModel.resetAllAdjustments()

        XCTAssertEqual(viewModel.document.adjustments, [])
        XCTAssertFalse(viewModel.hasAdjustments)
    }

    /// Reset-all must not touch the develop settings or the LUT — it is one panel's button.
    func testResetAllLeavesDevelopAndTheLUTAlone() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.updateDocument { $0.rawDevelop.exposure = 0.7 }
        viewModel.selectLUT(TestImages.warmLUT())
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5

        viewModel.resetAllAdjustments()

        XCTAssertEqual(viewModel.document.adjustments, [])
        XCTAssertEqual(viewModel.document.rawDevelop.exposure, 0.7, "develop is a different panel")
        XCTAssertNotNil(viewModel.document.lut.lutID, "the LUT is a different panel again")
    }
}

// MARK: - The tab

extension AdjustInspectorTests {

    /// Three tabs, in pipeline order left to right.
    func testTheInspectorHasThreeTabsInPipelineOrder() {
        XCTAssertEqual(AppViewModel.InspectorTab.allCases, [.info, .develop, .adjust])
        XCTAssertEqual(AppViewModel.InspectorTab.adjust.title, "Adjust")
    }

    /// The histogram is gated on the Info tab being on screen. Adjust is as much "a panel nobody is
    /// looking at" as Develop is, so switching to it must not start tallying pixels — the same
    /// finding `testTheDevelopTabDoesNotTallyAHistogram` pins for the other tab.
    func testTheAdjustTabDoesNotTallyAHistogram() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        // Switch first, *then* open: opening with Info showing would legitimately tally one — see
        // testNoHistogramIsTalliedWhileTheDevelopTabIsShowing for the same pitfall on the other tab.
        viewModel.inspectorTab = .adjust
        viewModel.isInspectorPresented = true
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        try await Task.sleep(for: .milliseconds(300))

        let requests = await fake.histogramRequests
        XCTAssertTrue(requests.isEmpty,
                      "the Adjust tab has no histogram; \(requests.count) tallies were issued")
    }
}

// MARK: - Render cost

extension AdjustInspectorTests {

    /// **An adjustment edit costs one render; a develop edit costs two.**
    ///
    /// `EditDocument.originalForComparison` keeps `rawDevelop` and strips `adjustments` (§8.5), so
    /// the comparison baseline moves when develop moves and stays put when an adjustment moves.
    /// That falls out of `pendingDevelopChange` never being set here, which is to say it works by
    /// accident of the current code — hence this test. Without it, a later edit that started
    /// scheduling the baseline unconditionally would double every slider tick's cost silently.
    func testAnAdjustmentEditDoesNotReRenderTheComparisonBaseline() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        // Let the opening renders settle so the count below is only this edit's.
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        try await Task.sleep(for: .milliseconds(200))
        let before = await fake.previewRequests.count

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        try await waitUntil("the adjusted render") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 1.5)] }
        }
        try await Task.sleep(for: .milliseconds(200))   // a second render would have landed by now

        let after = await fake.previewRequests.count
        XCTAssertEqual(after - before, 1,
                       "an adjustment must schedule the preview and nothing else; the A/B baseline "
                       + "strips adjustments, so it cannot have moved")
    }

    /// The other half of the same claim, so the test above cannot pass by the renderer being broken:
    /// a **develop** edit must still cost two.
    func testADevelopEditStillReRendersTheComparisonBaseline() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        try await Task.sleep(for: .milliseconds(200))
        let before = await fake.previewRequests.count

        viewModel.updateDocument { $0.rawDevelop.exposure = 0.7 }
        try await Task.sleep(for: .milliseconds(300))

        let after = await fake.previewRequests.count
        XCTAssertEqual(after - before, 2,
                       "a develop edit moves the baseline too — preview plus baseline")
    }
}
