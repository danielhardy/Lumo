import CoreGraphics
import XCTest
@testable import LumoKit

@MainActor
final class LookPreviewTests: XCTestCase {

    func testCandidatePreviewUsesThumbnailQualityAndDoesNotMutateActiveLook() async throws {
        let fake = FakeRenderEngine()
        let scheduler = ImageWorkScheduler()
        let coordinator = LookPreviewCoordinator(engine: fake, scheduler: scheduler)
        let source = ImageSource(data: Data([1, 2, 3]), nativeExtent: CGSize(width: 1200, height: 800))
        let look = TestImages.warmLUT()
        let active = EditDocument(lut: LUTSettings(lutID: TestImages.identityLUT().lutID, intensity: 0.35))

        let image = await coordinator.image(source: source, document: active, look: look)
        XCTAssertNotNil(image)
        XCTAssertEqual(active.lut.intensity, 0.35)

        let requests = await fake.renderRequests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.quality, .thumbnail)
        XCTAssertEqual(request.targetSize, LookPreviewLayout.renderSize)
        XCTAssertEqual(request.lut?.lutID, look.lutID)
        XCTAssertEqual(request.document.lut, LUTSettings(lutID: look.lutID, intensity: 1))
        XCTAssertEqual(request.document.light, active.light)
    }

    func testCandidatePreviewIsCachedBySourceDocumentAndLook() async throws {
        let fake = FakeRenderEngine()
        let scheduler = ImageWorkScheduler()
        let coordinator = LookPreviewCoordinator(engine: fake, scheduler: scheduler)
        let source = ImageSource(data: Data([4, 5, 6]), nativeExtent: CGSize(width: 1200, height: 800))
        let look = TestImages.warmLUT()
        let document = EditDocument()

        let first = await coordinator.image(source: source, document: document, look: look)
        let second = await coordinator.image(source: source, document: document, look: look)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)

        let renderRequestCount = await fake.renderRequests.count
        XCTAssertEqual(renderRequestCount, 1)
        XCTAssertEqual(coordinator.statistics.count, 1)
        XCTAssertGreaterThanOrEqual(coordinator.statistics.hits, 1)
    }

    func testNoSourceReturnsDeterministicFallbackSignalWithoutSchedulingRender() async {
        let fake = FakeRenderEngine()
        let scheduler = ImageWorkScheduler()
        let coordinator = LookPreviewCoordinator(engine: fake, scheduler: scheduler)

        let image = await coordinator.image(source: nil, document: EditDocument(), look: TestImages.warmLUT())

        XCTAssertNil(image)
        let renderRequestCount = await fake.renderRequests.count
        XCTAssertEqual(renderRequestCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testLookPreviewLayoutFitsTheSupportedInspectorWidths() {
        XCTAssertEqual(LookPreviewLayout.displaySize.height, 56)
        XCTAssertEqual(LookPreviewLayout.renderSize, CGSize(width: 168, height: 112))
        XCTAssertGreaterThanOrEqual(LookPreviewLayout.rowMinHeight, LookPreviewLayout.displaySize.height)

        // The thumbnail stays compact enough for the minimum inspector while leaving room for the
        // name, source badge, and selected-state checkmark.
        XCTAssertLessThan(LookPreviewLayout.displaySize.width, 100)
        XCTAssertGreaterThanOrEqual(LookPreviewLayout.displaySize.width, 72)
    }
}
