import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LumoKit

@MainActor
final class PreviewCoordinatorTests: XCTestCase {

    func testRapidInteractiveSubmissionsCoalesceToTheLatestDocument() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(
            engine: fake, interactiveDelay: .zero, settleDelay: .seconds(10)
        )
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        coordinator.beginInteraction()

        let source = makeSource()
        for step in 1...5 {
            let value = Double(step) / 10
            coordinator.submit(request(source: source, exposure: value), phase: .interactive)
        }

        try await waitUntil("one coalesced request") {
            await fake.requests.count == 1
        }
        let interactiveRequests = await fake.allRequests()
        XCTAssertEqual(interactiveRequests.first?.document.rawDevelop.exposure, 0.5)

        coordinator.endInteraction()
        try await waitUntil("the settled request") { await fake.requests.count == 2 }
        let allRequests = await fake.allRequests()
        XCTAssertEqual(allRequests[1].quality, .preview)
        XCTAssertEqual(allRequests[1].document.rawDevelop.exposure, 0.5)

        await fake.releaseNext()
        await fake.releaseNext()
        try await waitUntil("the settled publication") { publications.count == 1 }
        XCTAssertEqual(publications.first?.phase, .settled)
        XCTAssertEqual(publications.first?.request.quality, .preview)
        XCTAssertEqual(publications.first?.request.document.rawDevelop.exposure, 0.5)
    }

    func testAStaleResultCannotPublishAfterANewRevision() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(
            engine: fake, interactiveDelay: .zero, settleDelay: .zero
        )
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        let source = makeSource()

        coordinator.submit(request(source: source, exposure: 0.1))
        try await waitUntil("the first request") { await fake.requests.count == 1 }
        coordinator.submit(request(source: source, exposure: 0.5))
        try await waitUntil("the replacement request") { await fake.requests.count == 2 }

        await fake.releaseNext()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(publications.isEmpty, "the superseded result must not reach UI state")

        await fake.releaseNext()
        try await waitUntil("the current publication") { publications.count == 1 }
        XCTAssertEqual(publications[0].request.document.rawDevelop.exposure, 0.5)
        XCTAssertEqual(publications[0].revision, 2)
    }

    func testSettledGPUPublicationDoesNotRasterizeASecondImage() async throws {
        let fake = GPUBackedRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake)
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }

        coordinator.submit(request(source: makeSource(), exposure: 0.5))

        try await waitUntil("the GPU-backed settled publication") { publications.count == 1 }
        XCTAssertEqual(publications[0].phase, .settled)
        XCTAssertNotNil(publications[0].gpuImage)
        XCTAssertNil(publications[0].image)
        let makeCGImageCalls = await fake.makeCGImageCalls
        XCTAssertEqual(makeCGImageCalls, 0)
    }

    func testInteractiveUpdatesDoNotStartAnotherRenderWhileOneIsInFlight() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(
            engine: fake, interactiveDelay: .zero, settleDelay: .seconds(10)
        )
        coordinator.beginInteraction()
        let source = makeSource()

        coordinator.submit(request(source: source, exposure: 0.1), phase: .interactive)
        try await waitUntil("the first interactive request") { await fake.requests.count == 1 }

        for step in 2...5 {
            coordinator.submit(
                request(source: source, exposure: Double(step) / 10), phase: .interactive
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        let inFlightCount = await fake.requests.count
        XCTAssertEqual(inFlightCount, 1,
                       "superseded pointer values must remain value state, not queued renders")

        await fake.releaseNext()
        try await waitUntil("the latest interactive request") { await fake.requests.count == 2 }
        let requests = await fake.allRequests()
        XCTAssertEqual(requests[1].document.rawDevelop.exposure, 0.5)
        await fake.releaseNext()
        coordinator.endInteraction()
    }

    /// Opt-in smoke benchmark for the pointer-to-pixel path using a 60 MP-class source extent.
    /// The fake renderer keeps this repeatable in CI; the Instruments recipe remains the source of
    /// truth for hardware measurements with a real RAW and GPU.
    func testLargePreviewInteractiveLatencyBenchmark() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_BENCH"] != nil,
            "set LUMO_BENCH=1 to run the interactive latency benchmark"
        )

        let fake = FakeRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake, interactiveDelay: .zero)
        let source = ImageSource(
            url: URL(fileURLWithPath: "/tmp/60mp-tone-curve-test.raw"),
            nativeExtent: CGSize(width: 9_504, height: 6_336)
        )
        var publications = 0
        var samples: [Double] = []
        coordinator.onPublication = { publication in
            guard publication.phase == .interactive else { return }
            publications += 1
        }
        coordinator.beginInteraction()

        for step in 0..<20 {
            let before = Date()
            coordinator.submit(
                request(source: source, exposure: Double(step) / 20), phase: .interactive
            )
            try await waitUntil("interactive benchmark frame") { publications == step + 1 }
            samples.append(Date().timeIntervalSince(before) * 1_000)
        }
        coordinator.endInteraction()

        let sorted = samples.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        print(String(format: "tone-curve 60 MP-class pointer-to-pixel latency: p50 %.1f ms, p95 %.1f ms", p50, p95))
        XCTAssertLessThanOrEqual(p95, 50, "interactive preview must stay within the 50 ms budget")
    }

    private func request(source: ImageSource, exposure: Double) -> RenderRequest {
        RenderRequest(
            source: source,
            document: EditDocument(rawDevelop: RAWDevelopSettings(exposure: exposure)),
            targetSize: CGSize(width: 320, height: 240),
            quality: .preview,
            output: .raster
        )
    }

    private func makeSource() -> ImageSource {
        ImageSource(
            url: URL(fileURLWithPath: "/tmp/preview-coordinator-test.png"),
            nativeExtent: CGSize(width: 32, height: 24)
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 2,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline { return XCTFail("timed out waiting for (description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// A deterministic renderer that deliberately ignores task cancellation while a request is parked.
/// That models a renderer that has already entered a non-cancellable Core Image operation and proves
/// the coordinator's revision guard, rather than making the test pass only because cancellation was
/// observed before the renderer started.
private actor ControlledRenderEngine: RenderEngining {
    private(set) var requests: [RenderRequest] = []
    private var waiters: [(request: RenderRequest, continuation: CheckedContinuation<RenderResult, Never>)] = []

    func render(_ request: RenderRequest) async throws -> RenderResult {
        requests.append(request)
        return await withCheckedContinuation { continuation in
            waiters.append((request, continuation))
        }
    }

    func releaseNext() {
        guard !waiters.isEmpty else { return }
        let waiter = waiters.removeFirst()
        let request = waiter.request
        let continuation = waiter.continuation
        continuation.resume(returning: RenderResult(
            data: Self.pngData(), extent: CGSize(width: 2, height: 2), colorSpace: .current,
            quality: request.quality, output: request.output
        ))
    }

    func allRequests() -> [RenderRequest] { requests }

    func histogram(
        source: ImageSource, document: EditDocument, lut: CubeLUT?, scale: RenderScale,
        space: WorkingSpace, maxDimension: Int
    ) -> HistogramData? { nil }

    func invalidateLUTCache() {}
    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? { nil }

    private static func pngData() -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private actor GPUBackedRenderEngine: RenderEngining {
    private(set) var makeCGImageCalls = 0

    func makeCIImage(_ request: RenderRequest) async -> sending CIImage? {
        CIImage(color: CIColor(red: 0.5, green: 0.25, blue: 0.75)).cropped(
            to: CGRect(origin: .zero, size: request.targetSize ?? CGSize(width: 2, height: 2))
        )
    }

    func makeCGImage(_ request: RenderRequest) async -> sending CGImage? {
        makeCGImageCalls += 1
        return nil
    }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        fatalError("not used by this test")
    }

    func histogram(
        source: ImageSource, document: EditDocument, lut: CubeLUT?, scale: RenderScale,
        space: WorkingSpace, maxDimension: Int
    ) -> HistogramData? { nil }

    func invalidateLUTCache() {}
    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? { nil }
}
