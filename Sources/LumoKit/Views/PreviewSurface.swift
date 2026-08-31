import SwiftUI
import CoreImage
import MetalKit

/// GPU-owned presentation state for one preview. It is separate from AppViewModel so an
/// interactive frame does not invalidate the application's broad observation graph.
@MainActor
final class PreviewSurface: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    private(set) var image: CIImage?

    func present(_ image: CIImage?) {
        self.image = image
        revision &+= 1
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
        commandBuffer.commit()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        let context: CIContext = RenderEngine.presentationContext
        let device: MTLDevice = RenderEngine.presentationDevice
        let commandQueue: MTLCommandQueue = RenderEngine.presentationDevice.makeCommandQueue()!
    }
}
