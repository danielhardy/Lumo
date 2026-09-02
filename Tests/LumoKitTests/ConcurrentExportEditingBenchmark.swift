import XCTest
import Foundation
import AppKit
import CoreImage
import CoreMedia
import Darwin
import Metal
import MetalKit
import SwiftUI
@testable import LumoKit

/// Hardware-only benchmark for LUMO-113's outstanding acceptance criterion: a simultaneous batch
/// export and interactive editing session. This is intentionally opt-in. It uses the shipping
/// components — `ExportCoordinator` with an isolated export `RenderEngine`, `PreviewCoordinator`
/// over the bounded `ImageWorkScheduler` editor lane, histogram work admitted at `.histogram`
/// priority after confirmed settled frames, and `PreviewSurfaceView` presenting real
/// `CAMetalDrawable`s — so its numbers describe production, not the fake renderer. CI should keep
/// using the deterministic orchestration tests; this test produces no hardware claim unless
/// `LUMO_CONCURRENT_CAPTURE=1` is set on a logged-in macOS display.
@MainActor
final class ConcurrentExportEditingBenchmark: XCTestCase {
    private enum BenchmarkError: Error {
        case presentationTimedOut
    }

    /// Counter box shared between the publication handler and the driving loop.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }
        func reset() {
            lock.lock()
            value = 0
            lock.unlock()
        }
        var current: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private final class DrawableSizeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var size = CGSize.zero
        func set(_ newSize: CGSize) {
            lock.lock()
            size = newSize
            lock.unlock()
        }
        var current: CGSize {
            lock.lock()
            defer { lock.unlock() }
            return size
        }
    }

    /// Holds the installed MTKView so the benchmark can request draws. In production SwiftUI's
    /// `updateNSView` issues the display request; in a bare hosting view it does not flush, so the
    /// benchmark triggers it explicitly (the coordinator's pacer keeps later frames flowing).
    private final class MTKViewBox {
        weak var view: MTKView?
        func requestDraw() { view?.setNeedsDisplay(view?.bounds ?? .zero) }
    }

    private static func findMTKView(in view: NSView) -> MTKView? {
        if let mtk = view as? MTKView { return mtk }
        for subview in view.subviews {
            if let mtk = findMTKView(in: subview) { return mtk }
        }
        return nil
    }

    func testRealConcurrentBatchExportAndEditing() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_CONCURRENT_CAPTURE"] != nil,
            "set LUMO_CONCURRENT_CAPTURE=1 on a logged-in macOS display to run the concurrent capture"
        )
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable")
        }

        let environment = ProcessInfo.processInfo.environment
        let itemCount = max(1, Int(environment["LUMO_CONCURRENT_CAPTURE_ITEMS"] ?? "") ?? 6)
        let gestureCount = max(1, Int(environment["LUMO_CONCURRENT_CAPTURE_GESTURES"] ?? "") ?? 10)
        let framesPerGesture = max(1, Int(environment["LUMO_CONCURRENT_CAPTURE_FRAMES"] ?? "") ?? 6)

        // --- Sources --------------------------------------------------------
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/LumoKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let primaryPath = environment["LUMO_CONCURRENT_CAPTURE_RAW"]
            ?? repositoryRoot.appendingPathComponent("realworldtest/DSC07826.ARW").path
        let primaryURL = URL(fileURLWithPath: primaryPath)
        guard FileManager.default.fileExists(atPath: primaryURL.path) else {
            throw XCTSkip("capture source does not exist: \(primaryURL.path)")
        }
        // A second source gives the navigation phase a real source switch.
        let secondaryURL = environment["LUMO_CONCURRENT_CAPTURE_RAW_SECONDARY"].map(URL.init(fileURLWithPath:))
            ?? repositoryRoot.appendingPathComponent("realworldtest/DSC07241.ARW")
        let useSecondary = FileManager.default.fileExists(atPath: secondaryURL.path)

        let primaryDecoded = try ImageDecoder.load(from: primaryURL)
        let primarySource = ImageSource(
            url: primaryURL, nativeExtent: primaryDecoded.extent.integral.size
        )
        var secondarySource: ImageSource?
        if useSecondary {
            let secondaryDecoded = try ImageDecoder.load(from: secondaryURL)
            secondarySource = ImageSource(
                url: secondaryURL, nativeExtent: secondaryDecoded.extent.integral.size
            )
        }

        // --- Real drawable presentation (shipping PreviewSurfaceView path) --
        // Ask to become a regular GUI app so the WindowServer actually composites the capture
        // window; a background xctest process otherwise gets drawable handlers with presentedTime 0.
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        let surface = PreviewSurface()
        let drawableSizeBox = DrawableSizeBox()
        let hosting = NSHostingView(
            rootView: PreviewSurfaceView(
                surface: surface,
                onDrawableSizeChange: { drawableSizeBox.set($0) }
            )
        )
        let viewport = CGSize(width: 1280, height: 800)
        hosting.frame = CGRect(origin: .zero, size: viewport)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: viewport),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView?.wantsLayer = true
        window.contentView?.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.close() }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // Let AppKit commit the layer and the MTKView into the window before rendering.
        try await Task.sleep(for: .milliseconds(300))
        let mtkViewBox = MTKViewBox()
        mtkViewBox.view = Self.findMTKView(in: hosting)
        try XCTSkipIf(mtkViewBox.view == nil, "PreviewSurfaceView did not install an MTKView")

        // --- Shipping editors/scheduler/export wiring -----------------------
        let workScheduler = ImageWorkScheduler()
        let displayEngine = RenderEngine()
        let previewCoordinator = PreviewCoordinator(engine: displayEngine, scheduler: workScheduler)
        // Production batch exports use a second engine/context/queue; the coordinator's default
        // construction (engine is a RenderEngine) creates that isolated export engine.
        let exportCoordinator = ExportCoordinator(engine: displayEngine)

        let histogramJobID = ImageWorkScheduler.JobID("histogram")
        let settledPresentations = Counter()
        let histogramCompletions = Counter()

        previewCoordinator.onPublication = { publication in
            let request = publication.request
            let detailIdentity = PreviewFrameIdentity(
                sourceToken: request.source.traceToken,
                documentHash: request.document.editHash,
                space: request.space
            )
            let detailFactor = request.renderScale.factor(for: request.source.nativeExtent)
            let gpuImage = publication.gpuImage ?? publication.image.map { CIImage(cgImage: $0) }
            // Mirror AppViewModel.publishPreview + didPresentVisibleFrame: supporting work is
            // admitted only after the presentation surface confirms the settled frame.
            let presentationConfirmation: (() -> Void)? = publication.phase == .settled
                ? { settledPresentations.increment() }
                : nil
            if let gpuImage {
                surface.present(
                    gpuImage, space: request.space, revision: publication.revision,
                    telemetry: previewCoordinator.telemetry, source: request.source,
                    quality: request.quality, detailIdentity: detailIdentity,
                    detailFactor: detailFactor,
                    onPresented: presentationConfirmation
                )
                mtkViewBox.requestDraw()
            }
            if publication.phase == .settled, gpuImage != nil {
                workScheduler.enqueue(id: histogramJobID, lane: .editor, priority: .histogram) {
                    [displayEngine, histogramCompletions] in
                    guard !Task.isCancelled else { return }
                    let result = await displayEngine.histogram(
                        source: request.source, document: request.document, lut: request.lut,
                        scale: request.renderScale, space: request.space, maxDimension: 512
                    )
                    guard !Task.isCancelled, result != nil else { return }
                    histogramCompletions.increment()
                }
            }
        }
        previewCoordinator.onFailure = { _ in }
        // This capture host reports no drawable scan-out (presentedTime == 0). Hardware captures
        // still need input-to-present timestamps; opt into the same fallback clock the
        // MetalPresentationBenchmark capture procedure uses on such hosts. See PreviewSurface.
        surface.zeroPresentedTimeFallback = { LiveEditTelemetryClock.now }

        // --- Warmup: one settled render so the measured phase is warm -------
        let warmupStart = CACurrentMediaTime()
        previewCoordinator.submit(RenderRequest(
            source: primarySource, document: EditDocument(), targetSize: viewport,
            quality: .preview, output: .raster
        ), phase: .settled)
        try await Self.waitForPresentationCounter(
            settledPresentations, advances: 1, from: 0, timeout: 60
        )
        let warmupDevelopMS = (CACurrentMediaTime() - warmupStart) * 1_000
        // Let presentation plumbing settle, then start the measured phase with empty telemetry.
        try await Task.sleep(for: .milliseconds(300))
        previewCoordinator.telemetry.reset()
        settledPresentations.reset()
        histogramCompletions.reset()
        let initialMemory = residentMemory()

        // --- Start the batch export (production path, isolated engine) ------
        let batchDocument = EditDocument(light: LightAdjustments(
            exposure: 0.3, contrast: 10, highlights: -5, shadows: 5
        ))
        let items: [ExportCoordinator.BatchItem] = (0..<itemCount).map { index in
            let url = (index.isMultiple(of: 2) || !useSecondary) ? primaryURL : secondaryURL
            return ExportCoordinator.BatchItem(
                url: url, data: nil, name: "\(url.deletingPathExtension().lastPathComponent)-\(index)",
                document: batchDocument
            )
        }
        let outputDirectory = try Fixtures.makeTempDirectory("ConcurrentExportEditingBenchmark")
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let batchStart = CACurrentMediaTime()
        let exportTask = Task {
            await exportCoordinator.performBatchExport(
                items, document: batchDocument, lut: nil, format: .jpeg, to: outputDirectory
            )
        }

        // --- Concurrent editing workload ------------------------------------
        // Each gesture models a slider drag on the primary photo (a burst of interactive values
        // with the interaction held open), followed by real navigation to the secondary source
        // and back (coordinator cancel + settled source-switch requests).
        var navigationCycles = 0
        for gesture in 0..<gestureCount {
            let dragDocument = EditDocument(light: LightAdjustments(
                exposure: 0.2 + Double(gesture) * 0.02, contrast: 12, highlights: -8, shadows: 6
            ))

            let presentationBaseline = settledPresentations.current
            previewCoordinator.beginInteraction()
            for frame in 0..<framesPerGesture {
                previewCoordinator.submit(RenderRequest(
                    source: primarySource,
                    document: EditDocument(light: LightAdjustments(
                        exposure: dragDocument.light.exposure + Double(frame) * 0.04,
                        contrast: 12, highlights: -8, shadows: 6
                    )),
                    targetSize: viewport, quality: .interactive, output: .raster
                ), phase: .interactive)
                try await Task.sleep(for: .milliseconds(16))
            }
            previewCoordinator.endInteraction()
            try await Self.waitForPresentationCounter(
                settledPresentations, advances: 1, from: presentationBaseline, timeout: 30
            )

            if let secondarySource {
                // Navigation away and back: source-switch invalidation, then settled frames.
                previewCoordinator.cancel()
                previewCoordinator.submit(RenderRequest(
                    source: secondarySource, document: EditDocument(), targetSize: viewport,
                    quality: .preview, output: .raster
                ), phase: .settled)
                try await Self.waitForPresentationCounter(
                    settledPresentations, advances: 1, from: settledPresentations.current, timeout: 30
                )
                previewCoordinator.cancel()
                previewCoordinator.submit(RenderRequest(
                    source: primarySource, document: dragDocument, targetSize: viewport,
                    quality: .preview, output: .raster
                ), phase: .settled)
                try await Self.waitForPresentationCounter(
                    settledPresentations, advances: 1, from: settledPresentations.current, timeout: 30
                )
                navigationCycles += 1
            }
        }
        let editingEnd = CACurrentMediaTime()

        // --- Collect results --------------------------------------------------
        let outcome = await exportTask.value
        let batchEnd = CACurrentMediaTime()
        let batchDurationS = batchEnd - batchStart
        let editingDurationS = editingEnd - batchStart

        let telemetryReport = previewCoordinator.telemetry.report()
        let measurements = previewCoordinator.telemetry.measurements
        let interactiveLatencies = measurements
            .filter { $0.quality == .interactive }
            .compactMap(\.inputToPresent)
            .sorted()
        let settledLatencies = measurements
            .filter { $0.quality == .preview }
            .compactMap(\.inputToPresent)
            .sorted()
        func percentile(_ values: [Double], _ p: Double) -> Double? {
            guard !values.isEmpty else { return nil }
            return values[min(values.count - 1, Int(Double(values.count - 1) * p))]
        }
        let backing = drawableSizeBox.current
        let finalMemory = residentMemory()
        func optional(_ value: Double?) -> String {
            value.map { String(format: "%.3f", $0) } ?? "n/a"
        }
        let output: [(String, String)] = [
            ("scenario", "simultaneous-batch-export-and-editing"),
            ("source", primaryURL.lastPathComponent),
            ("navigation_source", useSecondary ? secondaryURL.lastPathComponent : "not available"),
            ("source_format", primaryURL.pathExtension.lowercased()),
            ("decoder", ImageDecoder.rawExtensions.contains(primaryURL.pathExtension.lowercased())
                ? "CIRAWFilter via ImageDecoder.load" : "ImageDecoder.load standard-image path"),
            ("source_extent", "\(Int(primaryDecoded.extent.width))x\(Int(primaryDecoded.extent.height))"),
            ("viewport_points", "\(Int(viewport.width))x\(Int(viewport.height))"),
            ("backing_pixels", "\(Int(backing.width))x\(Int(backing.height))"),
            ("requested_render_dimensions", "\(Int(viewport.width))x\(Int(viewport.height))"),
            ("warmup_develop_ms", String(format: "%.3f", warmupDevelopMS)),
            ("cache_state", "warm (settled preview develop completed before measurement)"),
            ("histogram_enabled", "true (per confirmed settled frame, .histogram priority)"),
            ("histogram_completions", String(histogramCompletions.current)),
            ("comparison_enabled", "false"),
            ("prefetch_enabled", "false"),
            ("editing_gestures", String(gestureCount)),
            ("interactive_frames_submitted", String(gestureCount * framesPerGesture)),
            ("navigation_cycles", String(navigationCycles)),
            ("editing_duration_s", String(format: "%.3f", editingDurationS)),
            ("batch_items", String(outcome.total)),
            ("batch_exported", String(outcome.exported)),
            ("batch_failed", String(outcome.failed)),
            ("batch_cancelled", String(outcome.isCancelled)),
            ("batch_duration_s", String(format: "%.3f", batchDurationS)),
            ("export_throughput_images_per_s", outcome.exported > 0
                ? String(format: "%.3f", Double(outcome.exported) / batchDurationS) : "n/a"),
            ("export_ms_per_image", outcome.exported > 0
                ? String(format: "%.1f", batchDurationS * 1_000 / Double(outcome.exported)) : "n/a"),
            ("editor_p50_input_to_present_ms", optional(telemetryReport.p50InputToPresentMS)),
            ("editor_p95_input_to_present_ms", optional(telemetryReport.p95InputToPresentMS)),
            ("editor_p99_input_to_present_ms", optional(telemetryReport.p99InputToPresentMS)),
            ("editor_worst_frame_gap_ms", String(format: "%.3f", telemetryReport.maximumFrameGapMS)),
            ("editor_delivered_fps", String(format: "%.2f", telemetryReport.deliveredFPS)),
            ("interactive_p95_input_to_present_ms", optional(percentile(interactiveLatencies, 0.95))),
            ("interactive_samples", String(interactiveLatencies.count)),
            ("settled_release_to_present_p95_ms", optional(percentile(settledLatencies, 0.95))),
            ("settled_samples", String(settledLatencies.count)),
            ("dropped_or_coalesced_values", String(telemetryReport.droppedOrCoalescedValues)),
            ("scheduler_dropped_editor_jobs", String(workScheduler.droppedEditorCount)),
            ("scheduler_cancellations", String(workScheduler.cancelledCount)),
            ("peak_memory_delta_bytes", String(max(0, finalMemory - initialMemory))),
            ("final_memory_delta_bytes", String(finalMemory - initialMemory)),
        ]
        print("CONCURRENT_EXPORT_EDIT_BENCHMARK "
              + output.map { "\($0.0)=\($0.1)" }.joined(separator: " "))

        // The capture is only meaningful if the concurrent export actually progressed.
        XCTAssertEqual(outcome.total, itemCount)
        XCTAssertEqual(outcome.isCancelled, false, "batch export must not be cancelled by editing")
        XCTAssertGreaterThan(outcome.exported, 0, "batch export must complete at least one item")
    }

    private static func waitForPresentationCounter(
        _ counter: Counter, advances: Int, from baseline: Int, timeout: TimeInterval
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while counter.current - baseline < advances {
            if Date() > deadline { throw BenchmarkError.presentationTimedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
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
