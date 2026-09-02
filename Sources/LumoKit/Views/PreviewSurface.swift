import SwiftUI
import CoreImage
import MetalKit

/// GPU-owned presentation state for one preview. It is separate from AppViewModel so an
/// interactive frame does not invalidate the application's broad observation graph.
struct PreviewFrameIdentity: Equatable, Sendable {
    let sourceToken: String
    let documentHash: String
    let space: WorkingSpace
}

@MainActor
final class PreviewSurface: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    private(set) var image: CIImage?
    private(set) var space: WorkingSpace = .current
    /// The last image known to have made it through the presentation command buffer. Production
    /// frames are already completed texture-backed images; the confirmation still matters because
    /// drawable acquisition/presentation can fail independently of processing.
    private var lastValidImage: CIImage?
    private var lastValidSpace: WorkingSpace = .current
    private var lastValidDetail: (identity: PreviewFrameIdentity, factor: CGFloat)?
    private var currentDetail: (identity: PreviewFrameIdentity, factor: CGFloat)?
    private var pendingDisplayID: UInt64?
    private var pendingGPURevision: UInt64?
    private struct PendingTelemetry {
        let telemetry: LiveEditTelemetry
        let source: ImageSource?
        let quality: RenderQuality
    }
    private var telemetryByRevision: [UInt64: PendingTelemetry] = [:]
    private var submittedTelemetryRevisions: Set<UInt64> = []
    private var presentationConfirmations: [UInt64: () -> Void] = [:]
    private var hasManagedPresentationLifecycle = false
    var onPresentationFailure: (() -> Void)?

    /// The Metal view calls this when a real presentation lifecycle exists. Headless/test callers
    /// have no drawable to confirm, so `present` confirms immediately for that compatibility seam.
    fileprivate func attachPresentationLifecycle() {
        hasManagedPresentationLifecycle = true
    }

    @discardableResult
    func present(_ image: CIImage?, space: WorkingSpace = .current, revision: UInt64? = nil,
                 telemetry: LiveEditTelemetry? = nil, source: ImageSource? = nil,
                 quality: RenderQuality = .interactive,
                 detailIdentity: PreviewFrameIdentity? = nil,
                 detailFactor: CGFloat? = nil,
                 onPresented: (() -> Void)? = nil) -> Bool {
        guard let image,
              image.extent.width > 0, image.extent.height > 0,
              image.extent.width.isFinite, image.extent.height.isFinite else {
            // A failed render must not turn the surface into a blank candidate. The coordinator
            // reports the failure separately; retaining the current image keeps the drawable's
            // last confirmed frame available while that path recovers.
            return false
        }
        if let detailIdentity, let detailFactor, detailFactor.isFinite,
           let current = currentDetail,
           current.identity == detailIdentity,
           detailFactor + 0.000001 < current.factor {
            // Navigation can legitimately request a cheaper interactive level, but it must not
            // replace an already valid sharper frame for the same source/document. The settled
            // request will still be accepted when it reaches the coordinator.
            return false
        }
        self.image = image
        self.space = space
        if let detailIdentity, let detailFactor, detailFactor.isFinite {
            currentDetail = (detailIdentity, detailFactor)
        } else {
            currentDetail = nil
        }
        self.revision &+= 1
        pendingDisplayID = self.revision
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
            if let onPresented {
                presentationConfirmations[revision] = onPresented
            }
            trimTelemetry()
        } else {
            pendingGPURevision = nil
        }
        if let revision, let onPresented, !hasManagedPresentationLifecycle {
            presentationConfirmations.removeValue(forKey: revision)
            onPresented()
        }
        return true
    }
    fileprivate func pendingPresentationRevision() -> UInt64? { pendingGPURevision }
    func pendingDisplayRevision() -> UInt64? { pendingDisplayID }

    func markPresentationSucceeded(displayRevision: UInt64) {
        guard pendingDisplayID == displayRevision else { return }
        lastValidImage = image
        lastValidSpace = space
        lastValidDetail = currentDetail
        pendingDisplayID = nil
    }

    func rejectPresentation(displayRevision: UInt64) {
        guard pendingDisplayID == displayRevision else { return }
        pendingDisplayID = nil
        image = lastValidImage
        space = lastValidSpace
        currentDetail = lastValidDetail
        revision &+= 1
        onPresentationFailure?()
    }

    fileprivate func markPresentationSubmitted(revision: UInt64) {
        guard telemetryByRevision[revision] != nil else { return }
        submittedTelemetryRevisions.insert(revision)
        if pendingGPURevision == revision { pendingGPURevision = nil }
    }

    fileprivate func setEffectiveDimensions(revision: UInt64, width: Int, height: Int) {
        telemetryByRevision[revision]?.telemetry.setEffectiveDimensions(revision, width: width, height: height)
    }

    fileprivate func markPresentationEncoded(revision: UInt64, drawableAcquisitionMS: Double,
                                             presentationEncodingMS: Double) {
        telemetryByRevision[revision]?.telemetry.markPresentationTimings(
            revision, drawableAcquisitionMS: drawableAcquisitionMS,
            presentationEncodingMS: presentationEncodingMS
        )
        if let pending = telemetryByRevision[revision], let source = pending.source {
            LumoObservability.event(
                .presentationEncoded, source: source, quality: pending.quality,
                detail: "drawable_ms=\(drawableAcquisitionMS) encode_ms=\(presentationEncodingMS)"
            )
        }
    }

    private func trimTelemetry() {
        guard telemetryByRevision.count > LiveEditTelemetry.maximumRetainedSamples else { return }
        let revisions = telemetryByRevision.keys.sorted()
        for revision in revisions.prefix(telemetryByRevision.count - LiveEditTelemetry.maximumRetainedSamples) {
            telemetryByRevision.removeValue(forKey: revision)
            submittedTelemetryRevisions.remove(revision)
        }
    }

    fileprivate func markGPUCompletion(revision: UInt64, time: TimeInterval) {
        guard let pending = telemetryByRevision[revision] else { return }
        pending.telemetry.mark(revision, gpuCompletion: time)
        if let source = pending.source {
            LumoObservability.liveEdit(.gpuComplete, source: source, quality: pending.quality,
                                       revision: revision)
        }
    }

    fileprivate func markPresentationFailed(revision: UInt64) {
        presentationConfirmations.removeValue(forKey: revision)
        telemetryByRevision.removeValue(forKey: revision)
        submittedTelemetryRevisions.remove(revision)
        if pendingGPURevision == revision { pendingGPURevision = nil }
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
        let confirmation = presentationConfirmations.removeValue(forKey: revision)
        confirmation?()
    }
    func clear() {
        image = nil
        space = .current
        lastValidImage = nil
        lastValidSpace = .current
        lastValidDetail = nil
        currentDetail = nil
        revision &+= 1
        pendingDisplayID = nil
        // A source switch invalidates any telemetry attached to the previous drawable. Its
        // command buffer may still complete, but it must not be attributed to the next source.
        pendingGPURevision = nil
        telemetryByRevision.removeAll()
        submittedTelemetryRevisions.removeAll()
        presentationConfirmations.removeAll()
    }
}

/// Persistent CAMetalLayer/MTKView destination for Core Image output.
struct PreviewSurfaceView: NSViewRepresentable {
    @ObservedObject var surface: PreviewSurface
    var navigation: CanvasNavigation = CanvasNavigation()
    var onScrollZoom: ((CGFloat) -> Void)?
    /// The drawable reports backing pixels, which is the only reliable size across mixed-DPI
    /// windows and side-by-side panels. SwiftUI point geometry is not sufficient here.
    var onDrawableSizeChange: ((CGSize) -> Void)?

    func makeNSView(context: Context) -> MTKView {
        let view = PreviewMTKView(frame: .zero, device: context.coordinator.device)
        surface.attachPresentationLifecycle()
        context.coordinator.surface = surface
        context.coordinator.navigation = navigation
        context.coordinator.onDrawableSizeChange = onDrawableSizeChange
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
        context.coordinator.onDrawableSizeChange = onDrawableSizeChange
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
        let commandQueue: MTLCommandQueue = RenderEngine.presentationQueue
        weak var surface: PreviewSurface?
        weak var view: MTKView?
        var navigation = CanvasNavigation()
        var onDrawableSizeChange: ((CGSize) -> Void)?
        private var lastDrawnRevision: UInt64?
        private var lastDrawnNavigation: CanvasNavigation?
        private var lastDrawableSize: (width: Int, height: Int)?
        /// Keep one drawable submission in flight and redraw only the newest surface state when it
        /// completes. Processing has already completed on RenderEngine's queue; this pacer bounds
        /// only the small transform/compositing pass and drawable submissions.
        private var isDrawing = false

        func draw(in view: MTKView) {
            self.view = view
            guard !isDrawing else { return }
            guard let surface, let image = surface.image else { return }
            let drawableAcquisitionStart = LiveEditTelemetryClock.now
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer()
            else { return }

            let drawableAcquisitionMS = max(
                0, (LiveEditTelemetryClock.now - drawableAcquisitionStart) * 1_000
            )

            let drawableSize = (drawable.texture.width, drawable.texture.height)
            onDrawableSizeChange?(CGSize(width: drawableSize.0, height: drawableSize.1))
            let sameDrawableSize = lastDrawableSize?.width == drawableSize.0 &&
                lastDrawableSize?.height == drawableSize.1
            // A pan/zoom/fit change does not bump `surface.revision` — it is presentation-only
            // and deliberately does not wait for a new render — so it must independently trigger
            // a redraw here, or dragging the image would have no visible effect until some other
            // change (an edit, a settled render) happened to bump the revision.
            guard surface.revision != lastDrawnRevision || !sameDrawableSize
                    || navigation != lastDrawnNavigation else {
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
            guard let output = Self.presentationImage(
                image, navigation: navigation, destination: destination
            ) else { return }
            let presentationRevision = surface.pendingPresentationRevision()
            if let presentationRevision {
                surface.setEffectiveDimensions(revision: presentationRevision,
                                               width: drawableSize.0, height: drawableSize.1)
            }
            let displayRevision = surface.pendingDisplayRevision()
            let drawRevision = surface.revision
            let drawNavigation = navigation
            isDrawing = true
            let presentationEncodingStart = LiveEditTelemetryClock.now
            context.render(output, to: drawable.texture, commandBuffer: commandBuffer,
                           bounds: destination, colorSpace: surface.space.cgColorSpace)

            // CIContext.render(_:to:commandBuffer:...) only encodes into this buffer; presenting the
            // drawable is on us. The drawable is submitted only after the complete fitted frame is
            // encoded, so a new frame cannot expose Core Image's intermediate tiles.
            commandBuffer.present(drawable)
            let presentationEncodingMS = max(
                0, (LiveEditTelemetryClock.now - presentationEncodingStart) * 1_000
            )
            if let presentationRevision {
                surface.markPresentationEncoded(
                    revision: presentationRevision,
                    drawableAcquisitionMS: drawableAcquisitionMS,
                    presentationEncodingMS: presentationEncodingMS
                )
            }
            commandBuffer.addCompletedHandler { [weak self, weak surface] commandBuffer in
                let succeeded = commandBuffer.status == .completed
                let gpuCompletion = commandBuffer.gpuEndTime > 0
                    ? commandBuffer.gpuEndTime : LiveEditTelemetryClock.now
                Task { @MainActor in
                    if let surface {
                        if succeeded, let displayRevision {
                            surface.markPresentationSucceeded(displayRevision: displayRevision)
                        } else if let displayRevision {
                            // A failed Core Image command buffer must not poison the drawable's
                            // last valid frame. Reject only the candidate this draw attempted;
                            // a newer publication may already be waiting behind it.
                            surface.rejectPresentation(displayRevision: displayRevision)
                        }
                        if let revision = presentationRevision {
                            if !succeeded { surface.markPresentationFailed(revision: revision) }
                            surface.markGPUCompletion(revision: revision, time: gpuCompletion)
                        }
                    }
                    self?.drawingFinished(
                        drawRevision: drawRevision, navigation: drawNavigation,
                        drawableSize: drawableSize, succeeded: succeeded
                    )
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
        }

        /// Build the bounded image graph sent to the drawable.
        ///
        /// A native-resolution candidate can be much larger than the drawable once navigation
        /// passes 100%. Leaving that transformed extent attached to the source-over graph makes
        /// Core Image's Metal destination evaluate an unnecessarily large working extent and can
        /// fail the command buffer on large sources. Clip before compositing the letterbox and
        /// clip the final result as a second explicit destination contract. The source image is
        /// never downscaled here; only pixels outside the current viewport are discarded.
        static func presentationImage(
            _ image: CIImage, navigation: CanvasNavigation, destination: CGRect
        ) -> CIImage? {
            guard destination.width > 0, destination.height > 0,
                  destination.width.isFinite, destination.height.isFinite,
                  image.extent.width > 0, image.extent.height > 0,
                  image.extent.width.isFinite, image.extent.height.isFinite else { return nil }

            let extent = image.extent
            let transform = navigation.transform(imageExtent: extent, viewportSize: destination.size)
            guard transform.scale.isFinite, transform.scale > 0,
                  transform.imageSize.width.isFinite, transform.imageSize.height.isFinite else {
                return nil
            }
            let displayed = image
                .transformed(by: transform.affineTransform(for: extent))
                .cropped(to: destination)
            // Deliberately dark image-presentation letterbox. This is scoped to the Metal
            // drawable so an image's surrounding SwiftUI shell can follow light/dark mode;
            // changing it would alter rendered presentation pixels rather than window chrome.
            let background = CIImage(
                color: CIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            ).cropped(to: destination)
            return displayed.composited(over: background).cropped(to: destination)
        }

        private func drawingFinished(
            drawRevision: UInt64, navigation: CanvasNavigation,
            drawableSize: (width: Int, height: Int), succeeded: Bool
        ) {
            isDrawing = false
            // Do not record a draw as complete until its command buffer completed successfully.
            // The surface may also have advanced while the buffer evaluated; in that case this
            // completion only frees the pacer and the newest revision is redrawn below.
            if succeeded, let surface, surface.revision == drawRevision, surface.image != nil {
                lastDrawnRevision = drawRevision
                lastDrawnNavigation = navigation
                lastDrawableSize = drawableSize
            } else {
                lastDrawnRevision = nil
                lastDrawnNavigation = nil
                lastDrawableSize = nil
            }
            // The surface may have advanced while this buffer evaluated. One redraw now consumes
            // that latest revision rather than replaying every superseded pointer update.
            if let view { view.setNeedsDisplay(view.bounds) }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            lastDrawableSize = nil
            onDrawableSizeChange?(CGSize(width: size.width.rounded(.down), height: size.height.rounded(.down)))
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
