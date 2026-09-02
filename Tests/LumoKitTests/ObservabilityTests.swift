import XCTest
@testable import LumoKit

final class ObservabilityTests: XCTestCase {

    func testWorkflowVocabularyHasStableNamesForEveryRequiredStage() {
        let names = LumoWorkflowStage.allCases.map { String(describing: $0.name) }

        XCTAssertEqual(names, [
            "Launch", "Scan", "Decode", "Render", "Cache", "PhotoSwitch", "Histogram", "Export", "LiveEdit",
            "PhotoTransfer", "PhotoThumbnail", "PhotoCollectionInsert",
        ])
    }

    func testWorkflowEventsCoverCacheAndSupersededWork() {
        let names = LumoWorkflowEvent.allCases.map { String(describing: $0.name) }

        XCTAssertEqual(names, ["CacheHit", "CacheMiss", "Cancellation", "Coalesced", "PointerInput", "RenderStart", "RenderEnd", "GPUComplete", "PresentationEncoded", "DrawablePresented", "StaleRevision"])
    }

    func testSourceTokensAreStablePrivateSafeAndDistinct() {
        let privatePath = "/Users/example/Private Photos/holiday/raw-001.dng"
        let first = LumoTraceContext(sourceFingerprint: privatePath, quality: "preview")
        let second = LumoTraceContext(sourceFingerprint: privatePath, quality: "preview")
        let different = LumoTraceContext(
            sourceFingerprint: "/Users/example/Private Photos/holiday/raw-002.dng",
            quality: "preview"
        )

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first.sourceToken, different.sourceToken)
        XCTAssertFalse(first.sourceToken.contains("Private"))
        XCTAssertFalse(first.sourceToken.contains("raw-001"))
        XCTAssertEqual(first.sourceToken.count, 16)
    }

    func testEndingAnIntervalMoreThanOnceIsSafe() {
        var interval = LumoSignpostInterval(.render, context: .unknown)
        interval.end()
        interval.end()
    }

    @MainActor
    func testLiveEditReportJoinsInputToPresentationAndQuantiles() {
        let source = ImageSource(url: URL(fileURLWithPath: "/tmp/telemetry.png"),
                                 nativeExtent: CGSize(width: 4000, height: 3000))
        let request = RenderRequest(source: source, document: EditDocument(), quality: .interactive, output: .raster)
        let telemetry = LiveEditTelemetry()
        telemetry.input(source: source, request: request, revision: 7, time: 10)
        telemetry.mark(7, renderStart: 10.001, renderEnd: 10.008,
                       gpuCompletion: 10.009, drawablePresentation: 10.020)

        let sample = telemetry.report().samples[0]
        XCTAssertEqual(sample.inputToPresent ?? -1, 20, accuracy: 0.0001)
        XCTAssertEqual(telemetry.report().p50InputToPresentMS ?? -1, 20, accuracy: 0.0001)
        XCTAssertEqual(sample.renderWidth, 4000)
        XCTAssertEqual(sample.renderHeight, 3000)
    }

    @MainActor
    func testLiveEditReportDoesNotTreatGPUCompletionAsPresentation() {
        let source = ImageSource(url: URL(fileURLWithPath: "/tmp/telemetry.png"),
                                 nativeExtent: CGSize(width: 4000, height: 3000))
        let request = RenderRequest(source: source, document: EditDocument(), quality: .interactive,
                                    output: .raster)
        let telemetry = LiveEditTelemetry()
        telemetry.input(source: source, request: request, revision: 8, time: 10)
        telemetry.mark(8, gpuCompletion: 10.010)

        XCTAssertNil(telemetry.report().samples[0].inputToPresent)
        XCTAssertNil(telemetry.report().p50InputToPresentMS)
        XCTAssertEqual(telemetry.report().deliveredFPS, 0)
    }

    @MainActor
    func testLiveEditRetentionIsBoundedAndEffectiveDimensionsAreRecorded() {
        let source = ImageSource(url: URL(fileURLWithPath: "/tmp/telemetry.png"),
                                 nativeExtent: CGSize(width: 4000, height: 3000))
        let request = RenderRequest(source: source, document: EditDocument(),
                                    targetSize: CGSize(width: 640, height: 480),
                                    quality: .interactive, output: .raster)
        let telemetry = LiveEditTelemetry()
        for revision in 1...300 {
            telemetry.input(source: source, request: request, revision: UInt64(revision), time: 10)
        }
        telemetry.setEffectiveDimensions(300, width: 1280, height: 720)

        let samples = telemetry.report().samples
        XCTAssertEqual(samples.count, LiveEditTelemetry.maximumRetainedSamples)
        XCTAssertNil(samples.first(where: { $0.revision == 1 }))
        XCTAssertEqual(samples.last?.requestedWidth, 640)
        XCTAssertEqual(samples.last?.requestedHeight, 480)
        XCTAssertEqual(samples.last?.effectiveWidth, 1280)
        XCTAssertEqual(samples.last?.effectiveHeight, 720)
    }
}
