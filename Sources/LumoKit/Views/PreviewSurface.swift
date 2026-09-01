import SwiftUI
import CoreImage
import MetalKit

/// GPU-owned presentation state for one preview. It is separate from AppViewModel so an
/// interactive frame does not invalidate the application's broad observation graph.
@MainActor
final class PreviewSurface: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    private(set) var image: CIImage?
    private(set) var space: WorkingSpace = .current
    private var pendingGPURevision: UInt64?
    private struct PendingTelemetry {
        let telemetry: LiveEditTelemetry
        let source: ImageSource?
        let quality: RenderQuality
    }
    private var telemetryByRevision: [UInt64: PendingTelemetry] = [:]
    private var submittedTelemetryRevisions: Set<UInt64> = []

    func present(_ image: CIImage?, space: WorkingSpace = .current, revision: UInt64? = nil,
                 telemetry: LiveEditTelemetry? = nil, source: ImageSource? = nil,
                 quality: RenderQuality = .interactive) {
        self.image = image
        self.space = space
        self.revision &+= 1
        if let revision, let telemetry {
            // A pending value that has not reached a drawable is obsolete once a newer value is
            // presented. Submitted values remain until Metal reports their completion/display.
            if let previous = pendingGPURevision,
               !submittedTelemetryRevisions.contains(previous) {
                telemetryByRevision.removeValue(forKey: previous)
            }
            pendingGPURevision = revision
            telemetryByRevision[revision] = PendingTelemetry(telemetry: telemetry, source: source,
                                                             quality: quality)
        } else {
            pendingGPURevision = nil
        }
    }
    fileprivate func pendingPresentationRevision() -> UInt64? { pendingGPURevision }

    fileprivate func markPresentationSubmitted(revision: UInt64) {
        guard telemetryByRevision[revision] != nil else { return }
        submittedTelemetryRevisions.insert(revision)
        if pendingGPURevision == revision { pendingGPURevision = nil }
    }

    fileprivate func markGPUCompletion(revision: UInt64, time: TimeInterval) {
        guard let pending = telemetryByRevision[revision] else { return }
        pending.telemetry.mark(revision, gpuCompletion: time)
        if let source = pending.source {
            LumoObservability.liveEdit(.gpuComplete, source: source, quality: pending.quality,
                                       revision: revision)
        }
    }

    fileprivate func markDrawablePresented(revision: UInt64, time: TimeInterval) {
        guard let pending = telemetryByRevision[revision] else { return }
        // Metal reports zero when a drawable was skipped. Do not turn a skipped frame into a
        // false presentation sample, but release its association so the next frame can be tracked.
        guard time > 0 else {
            telemetryByRevision.removeValue(forKey: revision)
            submittedTelemetryRevisions.remove(revision)
            return
        }
        pending.telemetry.mark(revision, drawablePresentation: time)
        if let source = pending.source {
            LumoObservability.liveEdit(.drawablePresented, source: source, quality: pending.quality,
                                       revision: revision, detail: "displayed")
        }
        telemetryByRevision.removeValue(forKey: revision)
        submittedTelemetryRevisions.remove(revision)
    }
    func clear() {
        image = nil
        space = .current
        revision &+= 1
        // A source switch invalidates any telemetry attached to the previous drawable. Its
        // command buffer may still complete, but it must not be attributed to the next source.
        pendingGPURevision = nil
        telemetryByRevision.removeAll()
        submittedTelemetryRevisions.removeAll()
    }
}

/// Persistent CAMetalLayer/MTKView destination for Core Image output.
struct PreviewSurfaceView: NSViewRepresentable {
    @ObservedObject var surface: PreviewSurface
    var navigation: CanvasNavigation = CanvasNavigation()
    var onScrollZoom: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> MTKView {
        let view = PreviewMTKView(frame: .zero, device: context.coordinator.device)
        context.coordinator.surface = surface
        context.coordinator.navigation = navigation
        view.onScrollZoom = onScrollZoom
        view.delegate = context.coordinator
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.autoResizeDrawable = true
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.surface = surface
        context.coordinator.navigation = navigation
        if let view = view as? PreviewMTKView { view.onScrollZoom = onScrollZoom }
        // SwiftUI may call updateNSView before the MTKView has a drawable (notably while a
        // NavigationSplitView is replacing the selected image). The delegate will retry when the
        // view is laid out and when it receives its next drawable instead of losing this revision.
        view.setNeedsDisplay(view.bounds)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator: NSObject, MTKViewDelegate {
        let context: CIContext = RenderEngine.presentationContext
        let device: MTLDevice = RenderEngine.presentationDevice
        let commandQueue: MTLCommandQueue = RenderEngine.presentationDevice.makeCommandQueue()!
        weak var surface: PreviewSurface?
        weak var view: MTKView?
        var navigation = CanvasNavigation()
        private var lastDrawnRevision: UInt64?
        private var lastDrawableSize: (width: Int, height: Int)?
        /// `makeCIImage` builds a lazy Core Image graph, so its completion is not the same thing
        /// as its GPU work finishing. Keep one drawable submission in flight and redraw only the
        /// newest surface state when it completes; otherwise a drag queues old curve revisions
        /// faster than the GPU can present them.
        private var isDrawing = false

        func draw(in view: MTKView) {
            self.view = view
            guard !isDrawing else { return }
            guard let surface, let image = surface.image,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer()
            else { return }

            let drawableSize = (drawable.texture.width, drawable.texture.height)
            let sameDrawableSize = lastDrawableSize?.width == drawableSize.0 &&
                lastDrawableSize?.height == drawableSize.1
            guard surface.revision != lastDrawnRevision || !sameDrawableSize else {
                return
            }

            let destination = CGRect(
                x: 0, y: 0,
                width: CGFloat(drawable.texture.width),
                height: CGFloat(drawable.texture.height)
            )
            guard destination.width > 0, destination.height > 0,
                  image.extent.width > 0, image.extent.height > 0,
                  image.extent.width.isFinite, image.extent.height.isFinite else { return }

            // Render into the drawable's actual pixel dimensions. The display transform is applied
            // here, after the requested render has been produced, so fit/fill/zoom/pan never alter
            // the source or export pipeline.
            let extent = image.extent
            let transform = navigation.transform(imageExtent: extent, viewportSize: destination.size)
            let displayed = image.transformed(by: transform.affineTransform(for: extent))
            // Deliberately dark image-presentation letterbox. This is scoped to the Metal
            // drawable so an image's surrounding SwiftUI shell can follow light/dark mode;
            // changing it would alter rendered presentation pixels rather than window chrome.
            let background = CIImage(
                color: CIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            ).cropped(to: destination)
            let output = displayed.composited(over: background)
            let presentationRevision = surface.pendingPresentationRevision()
            isDrawing = true
            context.render(output, to: drawable.texture, commandBuffer: commandBuffer,
                           bounds: destination, colorSpace: surface.space.cgColorSpace)

            // CIContext.render(_:to:commandBuffer:...) only encodes into this buffer; presenting the
            // drawable is on us. The drawable is submitted only after the complete fitted frame is
            // encoded, so a new frame cannot expose Core Image's intermediate tiles.
            commandBuffer.present(drawable)
            commandBuffer.addCompletedHandler { [weak self, weak surface] commandBuffer in
                if let revision = presentationRevision {
                    let gpuCompletion = commandBuffer.gpuEndTime > 0
                        ? commandBuffer.gpuEndTime : LiveEditTelemetryClock.now
                    Task { @MainActor in
                        surface?.markGPUCompletion(revision: revision, time: gpuCompletion)
                        self?.drawingFinished()
                    }
                } else {
                    Task { @MainActor in self?.drawingFinished() }
                }
            }
            if let revision = presentationRevision {
                drawable.addPresentedHandler { [weak surface] drawable in
                    let presentationTime = drawable.presentedTime
                    Task { @MainActor in
                        surface?.markDrawablePresented(revision: revision, time: presentationTime)
                    }
                }
            }
            commandBuffer.commit()
            if let revision = presentationRevision {
                surface.markPresentationSubmitted(revision: revision)
            }
            lastDrawnRevision = surface.revision
            lastDrawableSize = drawableSize
        }

        private func drawingFinished() {
            isDrawing = false
            // The surface may have advanced while this buffer evaluated. One redraw now consumes
            // that latest revision rather than replaying every superseded pointer update.
            if let view { view.setNeedsDisplay(view.bounds) }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            lastDrawableSize = nil
            view.setNeedsDisplay(view.bounds)
        }
    }
}

/// A paused MTKView still needs a display request after it first enters a window. This subclass
/// covers the case where SwiftUI's update arrived before the view had a drawable.
private final class PreviewMTKView: MTKView {
    var onScrollZoom: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        if delta.isFinite, abs(delta) > 0.001 {
            onScrollZoom?(pow(1.01, delta))
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setNeedsDisplay(bounds)
    }

    override func layout() {
        super.layout()
        setNeedsDisplay(bounds)
    }
}
