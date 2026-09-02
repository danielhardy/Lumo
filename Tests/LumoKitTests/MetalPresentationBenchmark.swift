import XCTest
import Foundation
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
    private enum BenchmarkError: Error {
        case cannotPresent
        case presentationTimedOut
        case renderFailed
    }

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
        let drawableAcquisitionMS: Double
        let presentationEncodingMS: Double
        let cpuEncodeMS: Double
        let gpuMS: Double?
        let memoryDeltaBytes: Int64
    }

    func testRealMetalPresentationBenchmark() async throws {
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
        // Core Image writes directly into the drawable texture. CAMetalLayer defaults to
        // framebuffer-only drawables, which makes CIRenderDestination reject the texture.
        layer.framebufferOnly = false
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
        let sourcePath = ProcessInfo.processInfo.environment["LUMO_METAL_BENCHMARK_RAW"]
        let decodedImage: CIImage
        let sourceName: String
        let sourceFormat: String
        let decoderDescription: String
        if let sourcePath {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw XCTSkip("LUMO_METAL_BENCHMARK_RAW does not exist: \(sourcePath)")
            }
            decodedImage = try ImageDecoder.load(from: sourceURL)
            sourceName = sourceURL.lastPathComponent
            sourceFormat = sourceURL.pathExtension.lowercased()
            decoderDescription = ImageDecoder.rawExtensions.contains(sourceURL.pathExtension.lowercased())
                ? "CIRAWFilter via ImageDecoder.load"
                : "ImageDecoder.load standard-image path"
        } else {
            decodedImage = CIImage(cgImage: try Fixtures.makeGradientCGImage(width: 1280, height: 800))
            sourceName = "generated-gradient"
            sourceFormat = "generated"
            decoderDescription = "synthetic gradient"
        }
        var temporarySourceDirectory: URL?
        let source: ImageSource
        if let sourcePath {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            source = ImageSource(url: sourceURL, nativeExtent: decodedImage.extent.integral.size)
        } else {
            let directory = try Fixtures.makeTempDirectory("MetalPresentationBenchmark")
            let generatedURL = try Fixtures.writeGradientPNG(
                width: 1280, height: 800, named: "generated-gradient.png", in: directory
            )
            temporarySourceDirectory = directory
            source = ImageSource(url: generatedURL, nativeExtent: decodedImage.extent.integral.size)
        }
        defer {
            if let temporarySourceDirectory {
                try? FileManager.default.removeItem(at: temporarySourceDirectory)
            }
        }
        let engine = RenderEngine()
        let drawableBounds = CGRect(origin: .zero, size: layer.drawableSize)
        let count = Int(ProcessInfo.processInfo.environment["LUMO_METAL_BENCHMARK_ITERATIONS"] ?? "20") ?? 20
        let iterations = max(5, min(count, 200))
        let settleIterations = 5
        let initialMemory = residentMemory()

        // Let AppKit commit the layer into the window before asking for the first drawable.
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        // This is the LUMO-107 boundary: source development and adjustment evaluation happen on
        // RenderEngine's actor-owned queue, and only the completed texture crosses to this actor.
        let warmupStart = CACurrentMediaTime()
        guard let completedWarmImage = await engine.makeCIImage(RenderRequest(
            source: source,
            document: .init(),
            targetSize: drawableBounds.size,
            quality: .interactive,
            output: .raster
        )) else {
            throw BenchmarkError.renderFailed
        }
        let warmupMS = (CACurrentMediaTime() - warmupStart) * 1_000

        var warmSamples: [Sample] = []
        for iteration in 0..<iterations {
            let input = CACurrentMediaTime()
            warmSamples.append(try present(
                completedWarmImage,
                inputTime: input,
                transformIteration: iteration,
                layer: layer,
                context: context,
                queue: queue,
                bounds: drawableBounds,
                initialMemory: initialMemory
            ))
        }

        // A release is represented by a warm .preview render with ordinary Light adjustments.
        // The source/developed cache is warm from the completed-texture setup above, while each
        // distinct exposure forces the adjustment stage to execute. The interval ends at the
        // drawable's presented callback, matching the user-visible settle target.
        var settledSamples: [Sample] = []
        for iteration in 0..<settleIterations {
            let settledInput = CACurrentMediaTime()
            let document = EditDocument(light: LightAdjustments(
                exposure: 0.45 + Double(iteration) * 0.05,
                contrast: 12,
                highlights: -8,
                shadows: 6
            ))
            guard let settledImage = await engine.makeCIImage(RenderRequest(
                source: source,
                document: document,
                targetSize: drawableBounds.size,
                quality: .preview,
                output: .raster
            )) else {
                throw BenchmarkError.renderFailed
            }
            settledSamples.append(try present(
                settledImage,
                inputTime: settledInput,
                transformIteration: iteration,
                layer: layer,
                context: context,
                queue: queue,
                bounds: drawableBounds,
                initialMemory: initialMemory
            ))
        }

        let latencies = warmSamples.map(\.inputToPresentMS).sorted()
        func percentile(_ values: [Double], _ p: Double) -> Double {
            let sorted = values.sorted()
            return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
        }
        func mean(_ values: [Double]) -> Double {
            values.reduce(0, +) / Double(values.count)
        }
        func optionalValues(_ samples: [Sample], _ value: (Sample) -> Double?) -> [Double] {
            samples.compactMap(value)
        }
        let displayTimes = warmSamples.map(\.inputToPresentMS)
        let worstGap = zip(displayTimes, displayTimes.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        let gpuSamples = optionalValues(warmSamples, \.gpuMS)
        let settledLatencies = settledSamples.map(\.inputToPresentMS)
        let settledGPU = optionalValues(settledSamples, \.gpuMS)
        let output = [
            "scenario": "completed-texture-presentation",
            "source": sourceName,
            "source_format": sourceFormat,
            "decoder": decoderDescription,
            "source_extent": "\(Int(decodedImage.extent.width))x\(Int(decodedImage.extent.height))",
            "viewport_pixels": "\(Int(layer.drawableSize.width))x\(Int(layer.drawableSize.height))",
            "requested_render_dimensions": "\(Int(drawableBounds.width))x\(Int(drawableBounds.height))",
            "effective_render_dimensions": "\(Int(drawableBounds.width))x\(Int(drawableBounds.height))",
            "warm_transform_iterations": String(warmSamples.count),
            "settled_adjustment_iterations": String(settledSamples.count),
            "completed_texture_warmup_ms": String(format: "%.3f", warmupMS),
            "p50_input_to_present_ms": String(format: "%.3f", percentile(latencies, 0.50)),
            "p95_input_to_present_ms": String(format: "%.3f", percentile(latencies, 0.95)),
            "p99_input_to_present_ms": String(format: "%.3f", percentile(latencies, 0.99)),
            "worst_sample_gap_ms": String(format: "%.3f", worstGap),
            "warm_drawable_acquisition_p50_ms": String(format: "%.3f", percentile(warmSamples.map(\.drawableAcquisitionMS), 0.50)),
            "warm_drawable_acquisition_p95_ms": String(format: "%.3f", percentile(warmSamples.map(\.drawableAcquisitionMS), 0.95)),
            "warm_presentation_encoding_p50_ms": String(format: "%.3f", percentile(warmSamples.map(\.presentationEncodingMS), 0.50)),
            "warm_presentation_encoding_p95_ms": String(format: "%.3f", percentile(warmSamples.map(\.presentationEncodingMS), 0.95)),
            "mean_cpu_encode_ms": String(format: "%.3f", mean(warmSamples.map(\.cpuEncodeMS))),
            "mean_gpu_ms": gpuSamples.isEmpty ? "unavailable" : String(format: "%.3f", gpuSamples.reduce(0, +) / Double(gpuSamples.count)),
            "warm_gpu_p95_ms": gpuSamples.isEmpty ? "unavailable" : String(format: "%.3f", percentile(gpuSamples, 0.95)),
            "release_to_settled_p50_ms": String(format: "%.3f", percentile(settledLatencies, 0.50)),
            "release_to_settled_p95_ms": String(format: "%.3f", percentile(settledLatencies, 0.95)),
            "release_to_settled_p99_ms": String(format: "%.3f", percentile(settledLatencies, 0.99)),
            "settled_drawable_acquisition_mean_ms": String(format: "%.3f", mean(settledSamples.map(\.drawableAcquisitionMS))),
            "settled_presentation_encoding_mean_ms": String(format: "%.3f", mean(settledSamples.map(\.presentationEncodingMS))),
            "settled_gpu_mean_ms": settledGPU.isEmpty ? "unavailable" : String(format: "%.3f", mean(settledGPU)),
            "peak_memory_delta_bytes": String(warmSamples.map(\.memoryDeltaBytes).max() ?? 0),
            "dropped_or_coalesced_values": "not applicable (direct benchmark; no pointer stream)",
            "note": "warm samples use the completed texture returned by RenderEngine; presentedTime is drawable presentation, not command-buffer completion"
        ].map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("METAL_PRESENTATION_BENCHMARK \(output)")
    }

    private func present(
        _ image: CIImage,
        inputTime: TimeInterval,
        transformIteration: Int,
        layer: CAMetalLayer,
        context: CIContext,
        queue: MTLCommandQueue,
        bounds: CGRect,
        initialMemory: Int64
    ) throws -> Sample {
        guard let drawable = layer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw BenchmarkError.cannotPresent
        }
        let acquisitionMS = max(0, (CACurrentMediaTime() - inputTime) * 1_000)
        let started = CACurrentMediaTime()
        let presentation = fit(image, to: bounds.size)
            .transformed(by: CGAffineTransform(translationX: CGFloat(transformIteration % 2), y: 0))
            .cropped(to: bounds)
        context.render(presentation, to: drawable.texture, commandBuffer: commandBuffer,
                       bounds: bounds, colorSpace: WorkingSpace.current.cgColorSpace)
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
        guard presentedSemaphore.wait(timeout: .now() + 2) == .success,
              let displayed = presented.get() else {
            throw BenchmarkError.presentationTimedOut
        }
        return Sample(
            inputToPresentMS: max(0, displayed - inputTime) * 1_000,
            drawableAcquisitionMS: acquisitionMS,
            presentationEncodingMS: (encoded - started) * 1_000,
            cpuEncodeMS: (encoded - started) * 1_000,
            gpuMS: gpuEnd > gpuStart ? (gpuEnd - gpuStart) * 1_000 : nil,
            memoryDeltaBytes: residentMemory() - initialMemory
        )
    }

    private func fit(_ image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let normalized = image.transformed(by: CGAffineTransform(
            translationX: -extent.origin.x, y: -extent.origin.y
        ))
        let scale = min(size.width / extent.width, size.height / extent.height)
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offset = CGPoint(
            x: (size.width - scaled.extent.width) / 2,
            y: (size.height - scaled.extent.height) / 2
        )
        return scaled
            .transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))
            .cropped(to: CGRect(origin: .zero, size: size))
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
