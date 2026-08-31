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
        let view = MTKView()
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        guard let image = surface.image, let drawable = view.currentDrawable else { return }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        context.coordinator.context.render(image, to: drawable.texture, commandBuffer: nil,
                                           bounds: image.extent, colorSpace: colorSpace)
        view.draw()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        let context: CIContext = RenderEngine.presentationContext
    }
}
