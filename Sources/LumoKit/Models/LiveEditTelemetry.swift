import Foundation
import QuartzCore

/// Metal command-buffer and drawable timestamps use the Core Animation host-time clock. Keep
/// input/render timestamps in that same clock so pointer-to-presentation latency is meaningful.
enum LiveEditTelemetryClock {
    static var now: TimeInterval { CACurrentMediaTime() }
}

struct LiveEditMeasurement: Sendable, Equatable {
    let sourceToken: String
    let revision: UInt64
    let quality: RenderQuality
    let renderWidth: Int
    let renderHeight: Int
    let requestedWidth: Int
    let requestedHeight: Int
    var effectiveWidth: Int
    var effectiveHeight: Int
    var inputTime: TimeInterval
    var renderStart: TimeInterval?
    var renderEnd: TimeInterval?
    var gpuCompletion: TimeInterval?
    var drawablePresentation: TimeInterval?
    /// Main-actor-only presentation timings. These are intentionally separate from renderStart/
    /// renderEnd: the latter covers completed source/adjustment processing on RenderEngine.
    var drawableAcquisitionMS: Double?
    var presentationEncodingMS: Double?
    /// Filled from Instruments/Metal System Trace when a capture is imported into a report.
    var cpuTimeMS: Double?
    var gpuTimeMS: Double?
    var allocationBytes: Int64?
    var memoryGrowthBytes: Int64?
    var coalescedValues: Int = 0
    var staleRevisionAge: UInt64 = 0

    var inputToPresent: TimeInterval? {
        guard let presented = drawablePresentation else { return nil }
        return max(0, (presented - inputTime) * 1_000)
    }
}

struct LiveEditReport: Sendable, Equatable {
    let samples: [LiveEditMeasurement]
    let p50InputToPresentMS: Double?
    let p95InputToPresentMS: Double?
    let p99InputToPresentMS: Double?
    let deliveredFPS: Double
    let maximumFrameGapMS: Double
    let droppedOrCoalescedValues: Int
    let maximumStaleRevisionAge: UInt64

    static func make(from samples: [LiveEditMeasurement]) -> Self {
        let presented = samples.filter { $0.drawablePresentation != nil }
        let latencies = presented.compactMap(\.inputToPresent).sorted()
        func percentile(_ p: Double) -> Double? {
            guard !latencies.isEmpty else { return nil }
            return latencies[min(latencies.count - 1, Int(Double(latencies.count - 1) * p))]
        }
        let times = presented.compactMap(\.drawablePresentation).sorted()
        let gaps = zip(times, times.dropFirst()).map { ($1 - $0) * 1_000 }
        let duration = (times.last ?? 0) - (times.first ?? 0)
        return Self(samples: samples, p50InputToPresentMS: percentile(0.50),
                    p95InputToPresentMS: percentile(0.95), p99InputToPresentMS: percentile(0.99),
                    deliveredFPS: duration > 0 ? Double(max(0, times.count - 1)) / duration : 0,
                    maximumFrameGapMS: gaps.max() ?? 0,
                    droppedOrCoalescedValues: samples.reduce(0) { $0 + $1.coalescedValues },
                    maximumStaleRevisionAge: samples.map(\.staleRevisionAge).max() ?? 0)
    }
}

/// Value-only live-edit measurements for the UI and deterministic orchestration tests. Hardware
/// CPU/GPU counters remain in the accompanying Instruments trace; drawable presentation is
/// timestamped by Metal's presented callback.
@MainActor
final class LiveEditTelemetry {
    static let maximumRetainedSamples = 256
    private(set) var measurements: [LiveEditMeasurement] = []
    private var index: [UInt64: Int] = [:]

    func input(source: ImageSource, request: RenderRequest, revision: UInt64,
               time: TimeInterval = LiveEditTelemetryClock.now) {
        let width = Int(request.targetSize?.width ?? source.nativeExtent.width)
        let height = Int(request.targetSize?.height ?? source.nativeExtent.height)
        measurements.append(LiveEditMeasurement(
            sourceToken: LumoTraceContext(source: source, quality: request.quality).sourceToken,
            revision: revision, quality: request.quality,
            renderWidth: width, renderHeight: height,
            requestedWidth: width, requestedHeight: height,
            effectiveWidth: width, effectiveHeight: height,
            inputTime: time, renderStart: nil, renderEnd: nil, gpuCompletion: nil,
            drawablePresentation: nil, drawableAcquisitionMS: nil, presentationEncodingMS: nil,
            cpuTimeMS: nil, gpuTimeMS: nil,
            allocationBytes: nil, memoryGrowthBytes: nil))
        trimIfNeeded()
        index[revision] = measurements.count - 1
    }

    func promote(from sourceRevision: UInt64, to revision: UInt64, source: ImageSource,
                 request: RenderRequest, time: TimeInterval = LiveEditTelemetryClock.now) {
        let inputTime = index[sourceRevision].map { measurements[$0].inputTime } ?? time
        input(source: source, request: request, revision: revision, time: inputTime)
    }

    func setEffectiveDimensions(_ revision: UInt64, width: Int, height: Int) {
        guard let i = index[revision] else { return }
        measurements[i].effectiveWidth = width
        measurements[i].effectiveHeight = height
    }

    func discard(_ revision: UInt64) {
        index.removeValue(forKey: revision)
    }

    func mark(_ revision: UInt64, renderStart: TimeInterval? = nil, renderEnd: TimeInterval? = nil,
              gpuCompletion: TimeInterval? = nil, drawablePresentation: TimeInterval? = nil) {
        guard let i = index[revision] else { return }
        if let value = renderStart { measurements[i].renderStart = value }
        if let value = renderEnd { measurements[i].renderEnd = value }
        if let value = gpuCompletion { measurements[i].gpuCompletion = value }
        if let value = drawablePresentation { measurements[i].drawablePresentation = value }
    }

    func markPresentationTimings(_ revision: UInt64, drawableAcquisitionMS: Double,
                                 presentationEncodingMS: Double) {
        guard let i = index[revision] else { return }
        measurements[i].drawableAcquisitionMS = drawableAcquisitionMS
        measurements[i].presentationEncodingMS = presentationEncodingMS
    }

    func coalesced(_ revision: UInt64) {
        guard let i = index[revision] else { return }
        measurements[i].coalescedValues += 1
    }

    func stale(_ revision: UInt64, age: UInt64) {
        guard let i = index[revision] else { return }
        measurements[i].staleRevisionAge = max(measurements[i].staleRevisionAge, age)
    }

    func report() -> LiveEditReport { .make(from: measurements) }
    func reset() { measurements.removeAll(); index.removeAll() }

    private func trimIfNeeded() {
        guard measurements.count > Self.maximumRetainedSamples else { return }
        let removeCount = measurements.count - Self.maximumRetainedSamples
        measurements.removeFirst(removeCount)
        index = Dictionary(uniqueKeysWithValues: measurements.enumerated().map { ($0.element.revision, $0.offset) })
    }
}
