import XCTest
import CoreImage
import CoreGraphics
import AppKit
@testable import LumoKit

/// Phase 2 Step 5 — the first step a user could see.
///
/// The gate is that the preview reflects **develop + adjustments + intensity**, all three of which
/// were unreachable before: the old path graded a baked `CIImage` with a LUT and nothing else.
///
/// Two kinds of test here, deliberately. The fake engine pins *what was asked for* — which document,
/// which scale, how many renders — without a GPU or a comparison tolerance. The real engine pins that
/// the pixels actually move, because a view model that assembles a perfect request and never renders
/// it would satisfy the first kind entirely.
@MainActor
final class PreviewCutoverTests: TempDirectoryTestCase {

    /// Written per test rather than in `setUp`: `XCTestCase.setUpWithError` is nonisolated, and this
    /// suite is `@MainActor` because the view model is.
    private func makeImageFile() throws -> URL {
        try Fixtures.writeGradientPNG(width: 64, height: 48, named: "shot.png", in: tempDirectory)
    }

    // MARK: - Waiting

    /// The load and the render are both unstructured tasks, so tests wait on published state rather
    /// than reading it straight after the call.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func openImage(_ viewModel: AppViewModel) async throws {
        viewModel.openImage(url: try makeImageFile())
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
    }

    /// Wait for a render request matching `predicate`.
    ///
    /// Polling for "the last request" is not good enough: several renders are in flight at once (the
    /// preview and the side-by-side baseline are separate requests), and an early one can satisfy a
    /// loose condition by accident — which is exactly how the first draft of the A/B test passed
    /// against the *opening* render instead of the one it meant to check.
    private func awaitRequest(
        _ fake: FakeRenderEngine,
        _ description: String,
        timeout: TimeInterval = 5,
        matching predicate: (FakeRenderEngine.Request) -> Bool
    ) async throws -> FakeRenderEngine.Request {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let match = await fake.previewRequests.first(where: predicate) { return match }
            try await Task.sleep(for: .milliseconds(10))
        }
        let seen = await fake.previewRequests
        XCTFail("timed out waiting for \(description); saw \(seen.count) request(s): \(seen)")
        throw XCTSkip("no matching request")
    }

    private func previewBytes(_ viewModel: AppViewModel) throws -> [UInt8] {
        let image = try XCTUnwrap(viewModel.previewSurface.image)
        let context = CIContext()
        let cg = try XCTUnwrap(context.createCGImage(image, from: image.extent.integral))
        return try Pixels.bytes(of: cg)
    }

    // MARK: - What the engine is asked for

    /// The whole document reaches the engine — not a LUT and an intensity, the document.
    func testTheDocumentReachesTheEngine() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openImage(viewModel)

        let first = try await awaitRequest(fake, "the opening render") { _ in true }
        XCTAssertEqual(first.document, EditDocument(), "an unedited image renders the empty document")
        XCTAssertNil(first.lutID)
        XCTAssertEqual(first.space, .current)

        // Opening an image issues two renders — the preview and the side-by-side baseline — and at
        // open they are indistinguishable. So assert the property of *every* request rather than
        // picking one: a mutation that rendered the preview at `.full` slipped past a version of this
        // test that only inspected `requests.first`, because it happened to read the other request.
        let all = await fake.previewRequests
        XCTAssertFalse(all.isEmpty)
        for request in all {
            guard case .preview(let box) = request.scale else {
                return XCTFail("every on-screen render must use a preview scale, got \(request.scale)")
            }
            XCTAssertEqual(box, CGSize(width: 1600, height: 1200))
        }
    }

    /// Navigation changes must remain a display concern while still driving a fresh render when
    /// more source detail is useful. The surface is intentionally asserted too: a request-only
    /// regression can look correct in the coordinator while leaving the visible canvas unchanged.
    func testFitFillAndExplicitZoomPublishNonBlankSurfaceFrames() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openImage(viewModel)
        try await waitUntil("the opening surface") { viewModel.previewSurface.image != nil }

        for action in [
            { viewModel.fitCanvas() },
            { viewModel.fillCanvas() },
            { viewModel.setCanvasZoom(4) },
        ] {
            let before = viewModel.previewSurface.revision
            action()
            try await waitUntil("the navigation render") {
                viewModel.previewSurface.revision > before && viewModel.previewSurface.image != nil
            }
        }

        let requests = await fake.previewRequests
        XCTAssertTrue(
            requests.contains {
                if case .preview(let size) = $0.scale {
                    return size == CGSize(width: 6_400, height: 4_800)
                }
                return false
            },
            "explicit zoom must request enough detail for the presentation transform"
        )
    }

    /// Develop, adjustments and intensity each reach the engine as part of the document. This is the
    /// step's gate, asserted at the request level.
    func testDevelopAdjustmentsAndIntensityAllReachTheEngine() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openImage(viewModel)

        let lut = TestImages.warmLUT()
        viewModel.selectLUT(lut)
        viewModel.updateDocument {
            $0.rawDevelop.exposure = 0.75
            $0.adjustments = [.vibrance(amount: 0.5), .exposure(ev: -0.25)]
            $0.lut.intensity = 0.4
        }

        // Match on the fully edited document, not on one field — several renders are in flight.
        let request = try await awaitRequest(fake, "the fully edited document") {
            $0.document.rawDevelop.exposure == 0.75 && !$0.document.adjustments.isEmpty
        }
        XCTAssertEqual(request.document.rawDevelop.exposure, 0.75, "develop must reach the renderer")
        XCTAssertEqual(request.document.adjustments,
                       [.vibrance(amount: 0.5), .exposure(ev: -0.25)],
                       "adjustments must reach the renderer, in order")
        XCTAssertEqual(request.document.lut.intensity, 0.4, "intensity must reach the renderer")
        XCTAssertEqual(request.lutID, lut.lutID, "the resolved LUT must reach the renderer")
    }

    /// Holding Space asks for the *comparison baseline* — develop kept, look removed (§8.5) — rather
    /// than a differently-decoded image.
    func testShowingOriginalRequestsTheDevelopAppliedBaseline() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openImage(viewModel)

        viewModel.selectLUT(TestImages.warmLUT())
        viewModel.updateDocument {
            $0.rawDevelop.exposure = 1.25
            $0.adjustments = [.vibrance(amount: 0.6)]
        }
        viewModel.showOriginal(true)

        // The baseline is a *specific* document: develop kept, everything else stripped. Waiting for
        // exactly that avoids matching the opening render, which also has no adjustments.
        let expected = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 1.25), adjustments: [], lut: .none
        )
        let request = try await awaitRequest(fake, "the A/B baseline render") {
            $0.document == expected
        }
        XCTAssertEqual(request.document.rawDevelop.exposure, 1.25,
                       "the A/B baseline keeps develop — it is the same negative, without the look")
        XCTAssertTrue(request.document.adjustments.isEmpty, "the baseline drops adjustments")
        XCTAssertNil(request.document.lut.lutID, "the baseline drops the LUT")
    }

    // MARK: - What actually reaches the screen

    /// The gate, at the pixels. Each of the three knobs must visibly move the preview — a request
    /// that is assembled correctly and never rendered would pass every test above.
    func testEachKnobVisiblyChangesThePreview() async throws {
        let viewModel = AppViewModel(engine: RenderEngine())
        try await openImage(viewModel)
        try await waitUntil("the first preview") { viewModel.previewSurface.image != nil }
        let plain = try previewBytes(viewModel)

        // 1. Adjustments.
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 1.0)] }
        try await waitUntil("the adjusted preview") { (try? self.previewBytes(viewModel)) != plain }
        let adjusted = try previewBytes(viewModel)
        assertPixelsDiffer(adjusted, plain, "an adjustment must change the preview")

        // 2. Develop. (Neutral develop is the plain decode, so this is a real change even for a
        //    standard image: `boostAmount` and friends are RAW-only, but exposure is not.)
        viewModel.updateDocument { $0.adjustments = [] }
        try await waitUntil("the reset preview") { (try? self.previewBytes(viewModel)) == plain }

        // 3. LUT and intensity.
        let lut = TestImages.warmLUT()
        viewModel.selectLUT(lut)
        try await waitUntil("the graded preview") { (try? self.previewBytes(viewModel)) != plain }
        let graded = try previewBytes(viewModel)
        assertPixelsDiffer(graded, plain, "selecting a LUT must change the preview")

        viewModel.setLUTIntensity(0.3)
        try await waitUntil("the weakened preview") { (try? self.previewBytes(viewModel)) != graded }
        let weakened = try previewBytes(viewModel)
        assertPixelsDiffer(weakened, graded, "intensity must change the preview")
        assertPixelsDiffer(weakened, plain, "…without collapsing back to ungraded")
    }

    /// **What Step 9 changed on screen**, through the real engine and the real preview property.
    ///
    /// The bug was not that the document held the wrong reference — it held the right one. It was
    /// that resolution missed, so `RenderPipeline` was handed `lut: nil` and rendered the image
    /// ungraded while the sidebar showed nothing selected. Every other Step 9 test drives the fake
    /// and asserts on the *request*; a request carrying the right LUT ID proves nothing about pixels
    /// if resolution hands the engine a nil.
    ///
    /// So this one rasterizes the GPU surface in the test: derive-shaped LUT, real `RenderEngine`,
    /// compare the published surface image
    /// before and after. It needs no RAW — the resolution path does not care what the source is —
    /// which is why it runs on CI too, unlike the derive gate proper.
    func testAFreshDerivePutsAGradedImageOnScreen() async throws {
        let viewModel = AppViewModel(engine: RenderEngine())
        try await openImage(viewModel)
        try await waitUntil("the first preview") { viewModel.previewSurface.image != nil }
        let ungraded = try previewBytes(viewModel)

        // Built the way DeriveCoordinator builds one, and delivered the way a finished derive
        // delivers it — through `onDerived`, which is the only path that selects a fresh derive.
        let derived = DeriveCoordinator.makeDerivedLUT(
            cube: TestImages.toBlackCube(size: 2), size: 2, name: "shot_recipe_2_Rec709"
        )
        viewModel.derive.onDerived?(derived)

        try await waitUntil("the derived preview") { (try? self.previewBytes(viewModel)) != ungraded }
        assertPixelsDiffer(try previewBytes(viewModel), ungraded,
                           "a finished derive must reach the screen, not leave it ungraded")
        XCTAssertEqual(viewModel.selectedLUT, derived, "…and show as selected in the sidebar")
    }

    /// Holding Space must actually put the ungraded image on screen.
    ///
    /// The fake cannot prove this: the side-by-side baseline issues an identical request, so a
    /// mutation that ignored `isShowingOriginal` entirely still produced a matching request and
    /// survived. What distinguishes them is which surface is published for the main panel, so this
    /// checks the pixels there.
    func testHoldingSpaceShowsTheUngradedImageInTheMainPanel() async throws {
        let viewModel = AppViewModel(engine: RenderEngine())
        try await openImage(viewModel)
        try await waitUntil("the first preview") { viewModel.previewSurface.image != nil }
        let ungraded = try previewBytes(viewModel)

        viewModel.selectLUT(TestImages.warmLUT())
        try await waitUntil("the graded preview") { (try? self.previewBytes(viewModel)) != ungraded }
        let graded = try previewBytes(viewModel)
        assertPixelsDiffer(graded, ungraded, "the LUT should be visible before comparing")

        viewModel.showOriginal(true)
        try await waitUntil("the comparison render") { (try? self.previewBytes(viewModel)) != graded }
        assertPixelsEqual(try previewBytes(viewModel), ungraded,
                          "holding Space must show the image without the look")

        viewModel.showOriginal(false)
        try await waitUntil("the graded preview to return") {
            (try? self.previewBytes(viewModel)) != ungraded
        }
        assertPixelsEqual(try previewBytes(viewModel), graded, "releasing Space must restore the look")
    }

    /// RAW develop reaching the screen, which is the half a standard image cannot exercise —
    /// `CIRAWFilter` is the only thing `rawDevelop` talks to. Skipped without a local RAW.
    func testRAWDevelopReachesThePreview() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }
        let viewModel = AppViewModel(engine: RenderEngine())
        viewModel.openImage(url: rawURL)
        try await waitUntil("the RAW to load", timeout: 30) { viewModel.sourceImage != nil }
        try await waitUntil("the first preview", timeout: 30) { viewModel.previewSurface.image != nil }
        let neutral = try previewBytes(viewModel)

        viewModel.updateDocument { $0.rawDevelop.exposure = 1.5 }
        try await waitUntil("the developed preview", timeout: 30) {
            (try? self.previewBytes(viewModel)) != neutral
        }
        assertPixelsDiffer(try previewBytes(viewModel), neutral,
                           "rawDevelop must reach CIRAWFilter through the preview path")
    }

    // MARK: - The shims still hold
    //
    // `processedImage` is gone — Step 6 deleted it along with the old export path. The test that
    // pinned its behaviour lived here and went with it; `ExportCutoverTests` is what replaces it.


    /// Views read `selectedLUT` and `lutIntensity`; both are now computed off the document. If they
    /// stopped tracking it the toolbar and sidebar would show stale state.
    func testTheShimsTrackTheDocument() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        XCTAssertNil(viewModel.selectedLUT)
        XCTAssertEqual(viewModel.lutIntensity, 1.0)

        viewModel.setLUTIntensity(0.35)
        XCTAssertEqual(viewModel.lutIntensity, 0.35)
        XCTAssertEqual(viewModel.document.lut.intensity, 0.35)

        // Built the way `DeriveCoordinator` builds one, not with a hand-rolled `CubeLUT`. The
        // hand-rolled version differed from production in exactly the field this line reads —
        // `lutID` — which is why this assertion was green while a fresh derive resolved to nothing.
        let lut = DeriveCoordinator.makeDerivedLUT(
            cube: TestImages.toBlackCube(size: 2), size: 2, name: "shot_recipe_2_Rec709"
        )
        viewModel.selectLUT(lut)
        XCTAssertEqual(viewModel.selectedLUT, lut, "an unsaved derived LUT must still resolve")
        XCTAssertEqual(viewModel.document.lut.lutID, lut.lutID)

        viewModel.selectLUT(nil)
        XCTAssertNil(viewModel.selectedLUT)
        XCTAssertNil(viewModel.document.lut.lutID)
        XCTAssertEqual(viewModel.lutIntensity, 0.35, "clearing the LUT keeps the chosen strength")
    }

    /// A file-backed LUT resolves out of the library by ID, and keeps resolving after a rescan —
    /// the property `LUTID` exists to guarantee (§4.3), now exercised through the view model.
    func testAFileBackedLUTResolvesAndSurvivesARescan() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 4), named: "Look.cube", in: tempDirectory)
        viewModel.library.scan(tempDirectory)
        try await waitUntil("the library scan") { !viewModel.library.isScanning }

        let lut = try XCTUnwrap(viewModel.library.allLUTs.first)
        viewModel.selectLUT(lut)
        XCTAssertEqual(viewModel.selectedLUT, lut)

        // What saving a derived LUT does: a new file lands and the library rescans.
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 4), named: "Another.cube", in: tempDirectory)
        viewModel.library.scan(tempDirectory)
        try await waitUntil("the rescan") { !viewModel.library.isScanning }

        XCTAssertEqual(viewModel.library.allLUTs.count, 2)
        XCTAssertEqual(viewModel.selectedLUT, lut, "the selection must survive a library rescan")
    }

}
