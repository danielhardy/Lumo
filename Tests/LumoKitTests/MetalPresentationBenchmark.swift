import XCTest
import AppKit
import CoreImage
import CoreMedia
import Darwin
import Metal
import QuartzCore
@testable import LumoKit

/// Hardware-only benchmark for the user-visible presentation path.
///
/// This is intentionally opt-in. Unlike PreviewCoordinatorTests, it owns a real CAMetalLayer,
/// obtains real CAMetalDrawables, renders through the shipping Metal CIContext, presents them, and
/// waits for the drawable's presented callback. It is therefore meaningful only on a logged-in
/// macOS session with a display. CI should keep using the deterministic orchestration tests.
@MainActor
final class MetalPresentationBenchmark: XCTestCase {
    private final class PresentationTimestamp: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TimeInterval?

        func set(_ value: TimeInterval) {
            lock.lock()
            self.value = value
            lock.unlock()
        }

        func get() -> TimeInterval? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private struct Sample: Codable {
        let inputToPresentMS: Double
        let cpuEncodeMS: Double
        let gpuMS: Double?
        let memoryDeltaBytes: Int64
    }

    func testRealMetalPresentationBenchmark() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_METAL_BENCHMARK"] != nil,
            "set LUMO_METAL_BENCHMARK=1 on a logged-in macOS display to run the hardware benchmark"
        )
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw XCTSkip("Metal is unavailable")
        }

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.drawableSize = CGSize(width: 1280, height: 800)
        layer.frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: layer.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let host = CALayer()
        host.frame = layer.frame
        host.addSublayer(layer)
        window.contentView?.layer = host
        window.contentView?.wantsLayer = true
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }

        let context = RenderEngine.presentationContext
        let image = CIImage(cgImage: try Fixtures.makeGradientCGImage(width: 1280, height: 800))
        let count = Int(ProcessInfo.processInfo.environment["LUMO_METAL_BENCHMARK_ITERATIONS"] ?? "20") ?? 20
        let iterations = max(5, min(count, 200))
        var samples: [Sample] = []
        let initialMemory = residentMemory()

        // Let AppKit commit the layer into the window before asking for the first drawable.
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        for iteration in 0..<iterations {
            guard let drawable = layer.nextDrawable(),
                  let commandBuffer = queue.makeCommandBuffer() else {
                throw XCTSkip("the display did not provide a drawable")
            }
            let input = CACurrentMediaTime()
            let started = CACurrentMediaTime()
            let presentation = image
                .transformed(by: CGAffineTransform(translationX: CGFloat(iteration % 2), y: 0))
                .cropped(to: CGRect(origin: .zero, size: layer.drawableSize))
            context.render(presentation, to: drawable.texture, commandBuffer: commandBuffer,
                           bounds: CGRect(origin: .zero, size: layer.drawableSize),
                           colorSpace: WorkingSpace.current.cgColorSpace)
            let encoded = CACurrentMediaTime()
            commandBuffer.present(drawable)

            let presented = PresentationTimestamp()
            let presentedSemaphore = DispatchSemaphore(value: 0)
            drawable.addPresentedHandler { drawable in
                presented.set(drawable.presentedTime > 0 ? drawable.presentedTime : CACurrentMediaTime())
                presentedSemaphore.signal()
            }
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            let gpuStart = commandBuffer.gpuStartTime
            let gpuEnd = commandBuffer.gpuEndTime
            _ = presentedSemaphore.wait(timeout: .now() + 2)
            let displayed = presented.get() ?? CACurrentMediaTime()
            samples.append(Sample(
                inputToPresentMS: max(0, displayed - input) * 1_000,
                cpuEncodeMS: (encoded - started) * 1_000,
                gpuMS: gpuEnd > gpuStart ? (gpuEnd - gpuStart) * 1_000 : nil,
                memoryDeltaBytes: residentMemory() - initialMemory
            ))
        }

        let latencies = samples.map(\.inputToPresentMS).sorted()
        func percentile(_ p: Double) -> Double { latencies[min(latencies.count - 1, Int(Double(latencies.count - 1) * p))] }
        let displayTimes = samples.map(\.inputToPresentMS)
        let worstGap = zip(displayTimes, displayTimes.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        let gpuSamples = samples.compactMap(\.gpuMS)
        let output = [
            "scenario": "real-metal-presentation",
            "iterations": String(samples.count),
            "p50_input_to_present_ms": String(format: "%.3f", percentile(0.50)),
            "p95_input_to_present_ms": String(format: "%.3f", percentile(0.95)),
            "p99_input_to_present_ms": String(format: "%.3f", percentile(0.99)),
            "worst_sample_gap_ms": String(format: "%.3f", worstGap),
            "mean_cpu_encode_ms": String(format: "%.3f", samples.map(\.cpuEncodeMS).reduce(0, +) / Double(samples.count)),
            "mean_gpu_ms": gpuSamples.isEmpty ? "unavailable" : String(format: "%.3f", gpuSamples.reduce(0, +) / Double(gpuSamples.count)),
            "peak_memory_delta_bytes": String(samples.map(\.memoryDeltaBytes).max() ?? 0),
            "note": "presentedTime is drawable presentation, not command-buffer completion"
        ].map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("METAL_PRESENTATION_BENCHMARK \(output)")
    }

    private func residentMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
