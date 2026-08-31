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
