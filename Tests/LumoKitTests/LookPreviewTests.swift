import CoreGraphics
import CoreImage
import XCTest

@testable import LumoKit

@MainActor
final class LookPreviewTests: XCTestCase {

    private actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { waiters.append($0) }
        }

        func releaseAll() {
            let parked = waiters
            waiters.removeAll()
            for waiter in parked { waiter.resume() }
        }
    }

    func testCandidatePreviewUsesThumbnailQualityAndDoesNotMutateActiveLook() async throws {
        let fake = FakeRenderEngine()
        let scheduler = ImageWorkScheduler()
        let coordinator = LookPreviewCoordinator(engine: fake, scheduler: scheduler)
        let source = ImageSource(
            data: Data([1, 2, 3]), nativeExtent: CGSize(width: 1200, height: 800))
        let look = TestImages.warmLUT()
        let active = EditDocument(
            lut: LUTSettings(lutID: TestImages.identityLUT().lutID, intensity: 0.35))

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
        let source = ImageSource(
            data: Data([4, 5, 6]), nativeExtent: CGSize(width: 1200, height: 800))
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

    func testCandidatePreviewUsesTheDirectImagePath() async throws {
        let engine = DirectLookRenderEngine()
        let coordinator = LookPreviewCoordinator(engine: engine, scheduler: ImageWorkScheduler())
        let source = ImageSource(
            data: Data([13, 14, 15]), nativeExtent: CGSize(width: 1200, height: 800))
        let look = TestImages.warmLUT()

        let image = await coordinator.image(source: source, document: EditDocument(), look: look)
        XCTAssertNotNil(image)
        let directCallCount = await engine.directCalls.count
        let encodedRenderCallCount = await engine.encodedRenderCalls
        XCTAssertEqual(directCallCount, 1)
        XCTAssertEqual(
            encodedRenderCallCount, 0,
            "a Look thumbnail must not encode a raster only to decode it again")
    }

    func testRapidDocumentGenerationsWaitForTheThumbnailCadence() async throws {
        let engine = DirectLookRenderEngine()
        let coordinator = LookPreviewCoordinator(engine: engine, scheduler: ImageWorkScheduler())
        let source = ImageSource(
            data: Data([19, 20, 21]), nativeExtent: CGSize(width: 1200, height: 800))
        let look = TestImages.warmLUT()
        var tasks: [Task<CGImage?, Never>] = []

        for step in 1...12 {
            let document: EditDocument = {
                var value = EditDocument()
                value.rawDevelop.exposure = Double(step) / 12
                return value
            }()
            tasks.append(
                Task {
                    await coordinator.image(source: source, document: document, look: look)
                })
        }

        try await Task.sleep(for: .milliseconds(20))
        let earlyCallCount = await engine.directCalls.count
        XCTAssertEqual(
            earlyCallCount, 0,
            "transient pointer values must not immediately enter the renderer")

        for task in tasks { _ = await task.value }
        let finalCallCount = await engine.directCalls.count
        XCTAssertEqual(finalCallCount, 1, "the burst should render only its latest generation")
    }

    func testNewerDocumentGenerationSupersedesQueuedLookPreview() async throws {
        let fake = FakeRenderEngine()
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 1
            ))
        let coordinator = LookPreviewCoordinator(engine: fake, scheduler: scheduler)
        let gate = Gate()
        let source = ImageSource(
            data: Data([16, 17, 18]), nativeExtent: CGSize(width: 1200, height: 800))
        let look = TestImages.warmLUT()

        scheduler.enqueue(id: .init("blocker"), lane: .thumbnail, priority: .background) {
            await gate.wait()
        }
        try await waitUntil("the blocker to start") { scheduler.runningThumbnailCount == 1 }

        let stale = Task {
            await coordinator.image(source: source, document: EditDocument(), look: look)
        }
        try await waitUntil("the stale Look preview to queue") {
            scheduler.pendingThumbnailCount == 1
        }

        var latestDocument = EditDocument()
        latestDocument.adjustments = [.exposure(ev: 0.75)]
        let latest = Task {
            await coordinator.image(source: source, document: latestDocument, look: look)
        }
        let staleImage = await stale.value
        XCTAssertNil(staleImage)
        try await waitUntil("the replacement Look preview to queue") {
            scheduler.pendingThumbnailCount == 1
        }
        XCTAssertEqual(
            scheduler.pendingThumbnailCount, 1,
            "the replacement should occupy the old logical slot")
        XCTAssertLessThanOrEqual(scheduler.peakQueuedThumbnailCount, 1)

        await gate.releaseAll()
        let latestImage = await latest.value
        XCTAssertNotNil(latestImage)
        let renderRequestCount = await fake.renderRequests.count
        XCTAssertEqual(
            renderRequestCount, 1, "the evicted generation must never reach the renderer")
    }

    func testNoSourceReturnsDeterministicFallbackSignalWithoutSchedulingRender() async {
        let fake = FakeRenderEngine()
        let scheduler = ImageWorkScheduler()
        let coordinator = LookPreviewCoordinator(engine: fake, scheduler: scheduler)

        let image = await coordinator.image(
            source: nil, document: EditDocument(), look: TestImages.warmLUT())

        XCTAssertNil(image)
        let renderRequestCount = await fake.renderRequests.count
        XCTAssertEqual(renderRequestCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testCancelAllCompletesQueuedPreviewAndAllowsTheSameLookToRetry() async throws {
        let fake = FakeRenderEngine()
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 1
            ))
        let coordinator = LookPreviewCoordinator(engine: fake, scheduler: scheduler)
        let gate = Gate()
        let source = ImageSource(
            data: Data([7, 8, 9]), nativeExtent: CGSize(width: 1200, height: 800))
        let look = TestImages.warmLUT()

        scheduler.enqueue(id: .init("blocker"), lane: .thumbnail, priority: .background) {
            await gate.wait()
        }
        try await waitUntil("the blocker to start") { scheduler.runningThumbnailCount == 1 }

        let pending = Task {
            await coordinator.image(source: source, document: EditDocument(), look: look)
        }
        try await waitUntil("the Look preview to queue") { scheduler.pendingThumbnailCount == 1 }

        scheduler.cancelAll()
        let cancelledImage = await pending.value
        XCTAssertNil(cancelledImage)
        XCTAssertEqual(scheduler.pendingCount, 0)

        await gate.releaseAll()
        let retry = await coordinator.image(source: source, document: EditDocument(), look: look)
        XCTAssertNotNil(retry)
        let renderRequestCount = await fake.renderRequests.count
        XCTAssertEqual(renderRequestCount, 1)
    }

    func testCancellingPreviewTaskCompletesItAndAllowsTheSameLookToRetry() async throws {
        let fake = FakeRenderEngine()
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 1
            ))
        let coordinator = LookPreviewCoordinator(engine: fake, scheduler: scheduler)
        let gate = Gate()
        let source = ImageSource(
            data: Data([10, 11, 12]), nativeExtent: CGSize(width: 1200, height: 800))
        let look = TestImages.warmLUT()

        scheduler.enqueue(id: .init("blocker"), lane: .thumbnail, priority: .background) {
            await gate.wait()
        }
        try await waitUntil("the blocker to start") { scheduler.runningThumbnailCount == 1 }

        let pending = Task {
            await coordinator.image(source: source, document: EditDocument(), look: look)
        }
        try await waitUntil("the Look preview to queue") { scheduler.pendingThumbnailCount == 1 }

        pending.cancel()
        let cancelledImage = await pending.value
        XCTAssertNil(cancelledImage)
        XCTAssertEqual(scheduler.pendingCount, 0)

        await gate.releaseAll()
        let retry = await coordinator.image(source: source, document: EditDocument(), look: look)
        XCTAssertNotNil(retry)
        let renderRequestCount = await fake.renderRequests.count
        XCTAssertEqual(renderRequestCount, 1)
    }

    func testLookPreviewLayoutFitsTheSupportedInspectorWidths() {
        XCTAssertEqual(LookPreviewLayout.displaySize.height, 56)
        XCTAssertEqual(LookPreviewLayout.renderSize, CGSize(width: 168, height: 112))
        XCTAssertGreaterThanOrEqual(
            LookPreviewLayout.rowMinHeight, LookPreviewLayout.displaySize.height)

        // The thumbnail stays compact enough for the minimum inspector while leaving room for the
        // name, source badge, and selected-state checkmark.
        XCTAssertLessThan(LookPreviewLayout.displaySize.width, 100)
        XCTAssertGreaterThanOrEqual(LookPreviewLayout.displaySize.width, 72)
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 2,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private actor DirectLookRenderEngine: RenderEngining {
    private(set) var directCalls: [RenderRequest] = []
    private(set) var encodedRenderCalls = 0

    func prepareSource(_ source: ImageSource) async -> ImageSourcePreparation? { nil }

    func makeCIImage(_ request: RenderRequest) async -> sending CIImage? { nil }

    func makeCGImage(_ request: RenderRequest) async -> sending CGImage? {
        directCalls.append(request)
        return FakeRenderEngine.solidImage()
    }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        encodedRenderCalls += 1
        throw ImageError.processingFailed
    }

    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        maxDimension: Int
    ) async -> HistogramData? { nil }

    func invalidateLUTCache() async {}

    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? { nil }
}
