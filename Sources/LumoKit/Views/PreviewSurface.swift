import SwiftUI
import CoreImage
import MetalKit

/// GPU-owned presentation state for one preview. It is separate from AppViewModel so an
/// interactive frame does not invalidate the application's broad observation graph.
@MainActor
final class PreviewSurface: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    private(set) var image: CIImage?
    private var pendingGPURevision: UInt64?
    private var pendingTelemetry: LiveEditTelemetry?
    private var pendingSource: ImageSource?
    private var pendingQuality: RenderQuality = .interactive

    func present(_ image: CIImage?, revision: UInt64? = nil, telemetry: LiveEditTelemetry? = nil,
                 source: ImageSource? = nil, quality: RenderQuality = .interactive) {
        self.image = image
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
    func clear() { present(nil) }
}

/// Persistent CAMetalLayer/MTKView destination for Core Image output.
struct PreviewSurfaceView: NSViewRepresentable {
    @ObservedObject var surface: PreviewSurface

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        guard let image = surface.image, let drawable = view.currentDrawable,
              let commandBuffer = context.coordinator.commandQueue.makeCommandBuffer()
        else { return }
        let colorSpace = WorkingSpace.current.cgColorSpace
        context.coordinator.context.render(image, to: drawable.texture, commandBuffer: commandBuffer,
                                           bounds: image.extent, colorSpace: colorSpace)
        // CIContext.render(_:to:commandBuffer:...) only encodes into this buffer; presenting the
        // drawable is on us, or the rendered texture never reaches the screen.
        commandBuffer.present(drawable)
        if let revision = surface.pendingPresentationRevision() {
            commandBuffer.addCompletedHandler { [weak surface] _ in
                Task { @MainActor in surface?.markGPUCompletion(revision: revision) }
            }
        }
        commandBuffer.commit()
        if let revision = surface.pendingPresentationRevision() {
            surface.markDrawablePresented(revision: revision)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        let context: CIContext = RenderEngine.presentationContext
        let device: MTLDevice = RenderEngine.presentationDevice
        let commandQueue: MTLCommandQueue = RenderEngine.presentationDevice.makeCommandQueue()!
    }
}
