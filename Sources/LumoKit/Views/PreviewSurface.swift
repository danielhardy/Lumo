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
    private var pendingTelemetry: LiveEditTelemetry?
    private var pendingSource: ImageSource?
    private var pendingQuality: RenderQuality = .interactive

    func present(_ image: CIImage?, space: WorkingSpace = .current, revision: UInt64? = nil,
                 telemetry: LiveEditTelemetry? = nil, source: ImageSource? = nil,
                 quality: RenderQuality = .interactive) {
        self.image = image
        self.space = space
        self.revision &+= 1
        if let revision, let telemetry {
            pendingGPURevision = revision
            pendingTelemetry = telemetry
            pendingSource = source
            pendingQuality = quality
        }
    }
    fileprivate func pendingPresentationRevision() -> UInt64? { pendingGPURevision }

    fileprivate func markGPUCompletion(revision: UInt64) {
        guard pendingGPURevision == revision, let telemetry = pendingTelemetry else { return }
        telemetry.mark(revision, gpuCompletion: Date.timeIntervalSinceReferenceDate)
        if let source = pendingSource {
            LumoObservability.liveEdit(.gpuComplete, source: source, quality: pendingQuality,
                                       revision: revision)
        }
        pendingGPURevision = nil
        pendingTelemetry = nil
        pendingSource = nil
    }

    fileprivate func markDrawablePresented(revision: UInt64) {
        guard pendingGPURevision == revision, let telemetry = pendingTelemetry else { return }
        telemetry.mark(revision, drawablePresentation: Date.timeIntervalSinceReferenceDate)
        if let source = pendingSource {
            LumoObservability.liveEdit(.drawablePresented, source: source, quality: pendingQuality,
                                       revision: revision, detail: "drawable-submitted")
        }
    }
    func clear() {
        image = nil
        space = .current
        revision &+= 1
        // A source switch invalidates any telemetry attached to the previous drawable. Its
        // command buffer may still complete, but it must not be attributed to the next source.
        pendingGPURevision = nil
        pendingTelemetry = nil
        pendingSource = nil
    }
}

/// Persistent CAMetalLayer/MTKView destination for Core Image output.
struct PreviewSurfaceView: NSViewRepresentable {
    @ObservedObject var surface: PreviewSurface

    func makeNSView(context: Context) -> MTKView {
        let view = PreviewMTKView(frame: .zero, device: context.coordinator.device)
        context.coordinator.surface = surface
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
        private var lastDrawnRevision: UInt64?
        private var lastDrawableSize: (width: Int, height: Int)?

        func draw(in view: MTKView) {
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

            // Render into the drawable's actual pixel dimensions. The request is based on the
            // whole preview canvas, while side-by-side panels have only half that width; using the
            // image extent directly can therefore clip or leave a partially updated texture.
            let extent = image.extent
            let scale = min(destination.width / extent.width, destination.height / extent.height)
            let fittedWidth = extent.width * scale
            let fittedHeight = extent.height * scale
            let transform = CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: (destination.width - fittedWidth) / 2 - extent.minX * scale,
                ty: (destination.height - fittedHeight) / 2 - extent.minY * scale
            )
            let fitted = image.transformed(by: transform)
            let background = CIImage(
                color: CIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            ).cropped(to: destination)
            let output = fitted.composited(over: background)
            context.render(output, to: drawable.texture, commandBuffer: commandBuffer,
                           bounds: destination, colorSpace: surface.space.cgColorSpace)

            // CIContext.render(_:to:commandBuffer:...) only encodes into this buffer; presenting the
            // drawable is on us. The drawable is submitted only after the complete fitted frame is
            // encoded, so a new frame cannot expose Core Image's intermediate tiles.
            commandBuffer.present(drawable)
            if let revision = surface.pendingPresentationRevision() {
                commandBuffer.addCompletedHandler { [weak surface] _ in
                    Task { @MainActor in surface?.markGPUCompletion(revision: revision) }
                }
            }
            commandBuffer.commit()
            lastDrawnRevision = surface.revision
            lastDrawableSize = drawableSize
            if let revision = surface.pendingPresentationRevision() {
                surface.markDrawablePresented(revision: revision)
            }
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
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setNeedsDisplay(bounds)
    }

    override func layout() {
        super.layout()
        setNeedsDisplay(bounds)
    }
}
