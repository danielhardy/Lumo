import XCTest
import QuartzCore
@testable import LumoKit

/// Opt-in microbenchmark for the value-only tracing calls used by the live-edit path.
/// It measures equivalent loops with signpost emission enabled and disabled; it is not a product
/// assertion because signpost cost depends on Instruments/log configuration and OS revision.
final class TracingOverheadBenchmark: XCTestCase {
    func testMeasureTracingOverhead() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_TRACE_BENCHMARK"] != nil,
            "set LUMO_TRACE_BENCHMARK=1 to measure tracing overhead"
        )
        let source = ImageSource(url: URL(fileURLWithPath: "/tmp/tracing-benchmark.png"),
                                 nativeExtent: CGSize(width: 1600, height: 1200))
        let iterations = 50_000
        let context = LumoTraceContext(source: source, quality: .interactive)
        let warmup = 1_000

        for _ in 0..<warmup {
            LumoObservability.event(.pointerInput, source: source, quality: .interactive,
                                    detail: "revision=1")
        }
        let enabledStart = CACurrentMediaTime()
        for revision in 0..<iterations {
            LumoObservability.event(.pointerInput, source: source, quality: .interactive,
                                    detail: "revision=\(revision)")
        }
        let enabledMS = (CACurrentMediaTime() - enabledStart) * 1_000

        // The disabled arm performs the same revision/detail construction while omitting only the
        // signpost emission. This isolates telemetry overhead from the benchmark's input loop.
        let disabledStart = CACurrentMediaTime()
        var sink = context.sourceToken
        for revision in 0..<iterations {
            sink = context.sourceToken + ":\(revision)"
        }
        let disabledMS = (CACurrentMediaTime() - disabledStart) * 1_000
        withExtendedLifetime(sink) {}

        print(String(format: "TRACING_OVERHEAD iterations=%d enabled_ms=%.3f disabled_ms=%.3f overhead_ms=%.3f overhead_per_event_us=%.3f",
                     iterations, enabledMS, disabledMS, enabledMS - disabledMS,
                     (enabledMS - disabledMS) * 1_000 / Double(iterations)))
    }
}
