import CoreGraphics
import Foundation
import Combine

/// High-frequency, presentation-only state for the editor canvas.
///
/// This object is intentionally separate from `AppViewModel`. Pan, zoom, and crop-handle
/// updates occur at pointer frequency and should invalidate only the canvas subtree. The
/// `AppViewModel` remains the owner of the committed `EditDocument`, history, rendering, and
/// persistence boundaries.
@MainActor
final class CanvasInteractionState: ObservableObject {
    @Published private(set) var navigation = CanvasNavigation()
    @Published private(set) var isCropToolActive = false
    @Published private(set) var cropDraft: CGRect?
    @Published private(set) var cropAspectRatio: CropAspectRatio = .freeform

    func resetForSource() {
        navigation.reset()
        isCropToolActive = false
        cropDraft = nil
        cropAspectRatio = .freeform
    }

    func fit() { navigation.fit() }
    func fill() { navigation.fill() }
    func reset() { navigation.reset() }

    func setZoom(_ value: CGFloat) {
        navigation.setZoom(value)
    }

    func pan(by delta: CGSize, imageExtent: CGRect, viewportSize: CGSize) {
        navigation.pan(by: delta, imageExtent: imageExtent, viewportSize: viewportSize)
    }

    @discardableResult
    func beginCrop(using committedCrop: CropAdjustments) -> Bool {
        guard !isCropToolActive else { return false }
        navigation.fit()
        isCropToolActive = true
        cropDraft = committedCrop.normalizedRect ?? CropAdjustments.unitRect
        cropAspectRatio = committedCrop.aspectRatio
        return true
    }

    func updateCropDraft(_ normalizedRect: CGRect) {
        guard isCropToolActive else { return }
        cropDraft = CropAdjustments(normalizedRect: normalizedRect).normalizedRect
    }

    func selectCropAspectRatio(_ aspectRatio: CropAspectRatio, imageSize: CGSize) {
        guard isCropToolActive else { return }
        let current = cropDraft ?? CropAdjustments.unitRect
        cropAspectRatio = aspectRatio
        cropDraft = CropOverlayInteraction.applying(
            aspectRatio, to: current, imageSize: imageSize
        )
    }

    func finishCrop() {
        isCropToolActive = false
        cropDraft = nil
        cropAspectRatio = .freeform
    }

    func resetCropDraft() {
        guard isCropToolActive else { return }
        cropDraft = CropAdjustments.unitRect
        cropAspectRatio = .freeform
    }
}

/// Transient presentation state for the editor canvas.
///
/// This is deliberately not part of `EditDocument`: changing how an image is viewed must never
/// change the pixels produced by export. The focal point is normalized to the source image so a
/// window/inspector resize can recompute the transform without losing the user's subject.
struct CanvasNavigation: Equatable, Sendable {
    enum Mode: String, CaseIterable, Sendable {
        case fit
        case fill
        case custom
    }

    static let minimumZoom: CGFloat = 0.1
    static let maximumZoom: CGFloat = 16

    private(set) var mode: Mode = .fit
    /// Multiplier over the mode's base scale. Fit and Fill both use 1; custom values are
    /// relative to fit, which makes the zoom control stable as the window changes size.
    private(set) var zoom: CGFloat = 1
    private(set) var focalPoint = CGPoint(x: 0.5, y: 0.5)

    var zoomPercent: Int { Int((zoom * 100).rounded()) }

    mutating func fit() {
        mode = .fit
        zoom = 1
        focalPoint = Self.center
    }

    mutating func fill() {
        mode = .fill
        zoom = 1
        focalPoint = Self.center
    }

    mutating func reset() { fit() }

    mutating func setZoom(_ value: CGFloat) {
        mode = .custom
        zoom = Self.clampZoom(value)
    }

    mutating func multiplyZoom(by factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        setZoom(zoom * factor)
    }

    /// Pan in the coordinate space of the visible SwiftUI canvas. The focal point representation
    /// makes the result independent of backing scale and keeps it stable through layout changes.
    mutating func pan(by delta: CGSize, imageExtent: CGRect, viewportSize: CGSize) {
        guard delta.width.isFinite, delta.height.isFinite else { return }
        let transform = Self.transform(
            imageExtent: imageExtent, viewportSize: viewportSize,
            mode: mode, zoom: zoom, focalPoint: focalPoint
        )
        focalPoint = Self.focalPoint(
            afterMovingOrigin: CGSize(width: transform.origin.x + delta.width,
                                      height: transform.origin.y + delta.height),
            imageExtent: imageExtent, viewportSize: viewportSize,
            scale: transform.scale
        )
    }

    /// The image placement used by both the raster fallback and the Metal presentation surface.
    func transform(imageExtent: CGRect, viewportSize: CGSize) -> CanvasTransform {
        Self.transform(
            imageExtent: imageExtent, viewportSize: viewportSize,
            mode: mode, zoom: zoom, focalPoint: focalPoint
        )
    }

    /// How much more source resolution is useful than a fit render. This feeds preview requests;
    /// the render pipeline still refuses to upscale beyond the native image extent.
    func renderResolutionMultiplier(imageExtent: CGSize, viewportSize: CGSize) -> CGFloat {
        guard Self.isValidSize(imageExtent), Self.isValidSize(viewportSize) else { return 1 }
        let fit = min(viewportSize.width / imageExtent.width,
                      viewportSize.height / imageExtent.height)
        guard fit.isFinite, fit > 0 else { return 1 }
        return max(1, min(Self.maximumZoom, transform(
            imageExtent: CGRect(origin: .zero, size: imageExtent),
            viewportSize: viewportSize
        ).scale / fit))
    }

    static let center = CGPoint(x: 0.5, y: 0.5)

    static func clampZoom(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        return min(max(value, minimumZoom), maximumZoom)
    }

    private static func transform(
        imageExtent: CGRect, viewportSize: CGSize, mode: Mode, zoom: CGFloat,
        focalPoint: CGPoint
    ) -> CanvasTransform {
        guard isValidSize(imageExtent.size), isValidSize(viewportSize) else {
            return CanvasTransform(scale: 1, origin: .zero, imageSize: .zero)
        }

        let fitScale = min(viewportSize.width / imageExtent.width,
                           viewportSize.height / imageExtent.height)
        let fillScale = max(viewportSize.width / imageExtent.width,
                            viewportSize.height / imageExtent.height)
        let baseScale = mode == .fill ? fillScale : fitScale
        let scale = baseScale * clampZoom(zoom)
        let imageSize = CGSize(width: imageExtent.width * scale,
                               height: imageExtent.height * scale)
        let focal = CGPoint(x: min(max(focalPoint.x, 0), 1),
                            y: min(max(focalPoint.y, 0), 1))
        let centeredOrigin = CGPoint(
            x: viewportSize.width / 2 - focal.x * imageSize.width,
            y: viewportSize.height / 2 - focal.y * imageSize.height
        )
        let origin = CGPoint(
            x: constrainedOrigin(centeredOrigin.x, content: imageSize.width,
                                  viewport: viewportSize.width),
            y: constrainedOrigin(centeredOrigin.y, content: imageSize.height,
                                  viewport: viewportSize.height)
        )
        return CanvasTransform(scale: scale, origin: origin, imageSize: imageSize)
    }

    private static func focalPoint(
        afterMovingOrigin origin: CGSize, imageExtent: CGRect, viewportSize: CGSize, scale: CGFloat
    ) -> CGPoint {
        guard isValidSize(imageExtent.size), isValidSize(viewportSize), scale.isFinite, scale > 0
        else { return center }
        let imageSize = CGSize(width: imageExtent.width * scale, height: imageExtent.height * scale)
        let constrainedX = constrainedOrigin(origin.width, content: imageSize.width,
                                              viewport: viewportSize.width)
        let constrainedY = constrainedOrigin(origin.height, content: imageSize.height,
                                              viewport: viewportSize.height)
        return CGPoint(
            x: min(max((viewportSize.width / 2 - constrainedX) / imageSize.width, 0), 1),
            y: min(max((viewportSize.height / 2 - constrainedY) / imageSize.height, 0), 1)
        )
    }

    private static func constrainedOrigin(_ origin: CGFloat, content: CGFloat, viewport: CGFloat) -> CGFloat {
        guard content.isFinite, content > 0, viewport.isFinite, viewport > 0 else { return 0 }
        guard content > viewport else { return (viewport - content) / 2 }
        return min(max(origin, viewport - content), 0)
    }

    private static func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}

struct CanvasTransform: Equatable, Sendable {
    let scale: CGFloat
    /// Origin of the displayed image in the drawable's Core Image (bottom-left) coordinate system.
    let origin: CGPoint
    let imageSize: CGSize

    func affineTransform(for imageExtent: CGRect) -> CGAffineTransform {
        CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: origin.x - imageExtent.minX * scale,
            ty: origin.y - imageExtent.minY * scale
        )
    }
}
