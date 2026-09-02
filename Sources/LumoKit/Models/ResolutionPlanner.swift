import CoreGraphics
import Foundation

/// The discrete source detail selected for one canvas request.
///
/// `sourceSize` is the size of the *uncropped* source that should be developed. Crop remains a
/// later composition stage, so a small crop can legitimately select native source detail even when
/// the visible crop itself is only a fraction of the source. The visible region is retained as
/// metadata for profiling and a future ROI/tile implementation; it does not move crop ahead of
/// spatial effects.
struct ResolutionPlan: Equatable, Sendable {
    let level: Int
    let scale: CGFloat
    let requiredScale: CGFloat
    let sourceSize: CGSize
    let cropRect: CGRect
    let visibleSourceRect: CGRect
    let isNativeResolution: Bool

    var pixelCount: Int {
        let width = max(0, Int(sourceSize.width.rounded(.down)))
        let height = max(0, Int(sourceSize.height.rounded(.down)))
        return width.multipliedReportingOverflow(by: height).overflow
            ? Int.max : width * height
    }
}

/// Chooses a bounded, reusable resolution pyramid for the canvas.
///
/// The planner works in source-pixel scale rather than viewport-point scale. This makes it correct
/// for mixed-DPI displays and for side-by-side panels, provided the viewport is the panel's actual
/// backing-pixel size. Levels are deliberately few: a zoom gesture should revisit cache entries,
/// not manufacture one for every fractional magnification value.
struct ResolutionPlanner: Equatable, Sendable {
    /// Enough granularity for a preview while keeping the source-cache working set bounded. The
    /// native level is always the final safety net for small crops and deep inspection.
    static let detailScales: [CGFloat] = [0.125, 0.25, 0.5, 0.75, 1.0]
    static let downgradeHysteresis: CGFloat = 0.85

    private(set) var selectedLevel: Int?

    init() { selectedLevel = nil }

    mutating func reset() { selectedLevel = nil }

    mutating func plan(
        nativeExtent: CGSize,
        crop: CropAdjustments = .neutral,
        viewportSize: CGSize,
        navigation: CanvasNavigation = CanvasNavigation()
    ) -> ResolutionPlan {
        let validNative = Self.isValidSize(nativeExtent)
        let native = validNative ? nativeExtent : CGSize(width: 1, height: 1)
        let rect = crop.normalizedRect ?? CropAdjustments.unitRect
        let cropSize = CGSize(width: native.width * rect.width, height: native.height * rect.height)
        let validViewport = Self.isValidSize(viewportSize)

        let fitScale: CGFloat
        let transform: CanvasTransform
        if validViewport, Self.isValidSize(cropSize) {
            transform = navigation.transform(
                imageExtent: CGRect(origin: .zero, size: cropSize), viewportSize: viewportSize
            )
            fitScale = min(viewportSize.width / cropSize.width,
                           viewportSize.height / cropSize.height)
        } else {
            transform = CanvasTransform(scale: 1, origin: .zero, imageSize: cropSize)
            fitScale = 1
        }

        // Never choose less detail than a fit preview. A custom zoom below 1.0 changes presentation,
        // but it should not cause a previously useful source level to be discarded.
        let requestedScale = max(fitScale, transform.scale)
        let requiredScale = min(max(requestedScale.isFinite ? requestedScale : 1, 0), 1)
        let level = Self.level(for: requiredScale, current: selectedLevel)
        selectedLevel = level
        let scale = Self.detailScales[level]
        let sourceSize = CGSize(
            width: max(1, min(native.width, (native.width * scale).rounded(.toNearestOrAwayFromZero))),
            height: max(1, min(native.height, (native.height * scale).rounded(.toNearestOrAwayFromZero)))
        )

        return ResolutionPlan(
            level: level,
            scale: scale,
            requiredScale: requiredScale,
            sourceSize: sourceSize,
            cropRect: rect,
            visibleSourceRect: Self.visibleSourceRect(
                cropRect: rect, nativeExtent: native, cropSize: cropSize,
                transform: transform, viewportSize: viewportSize
            ),
            isNativeResolution: level == Self.detailScales.count - 1 || requiredScale >= 1
        )
    }

    private static func level(for required: CGFloat, current: Int?) -> Int {
        let adequate = detailScales.firstIndex { $0 >= required } ?? detailScales.count - 1
        guard let current, detailScales.indices.contains(current) else { return adequate }

        // Upgrades happen as soon as the current level is no longer adequate. A downgrade waits
        // until the next lower level has meaningful headroom, preventing boundary thrashing while
        // the user moves a pinch or resizes a window by a few pixels.
        if required > detailScales[current] { return adequate }
        guard current > 0 else { return current }
        let lower = current - 1
        return required <= detailScales[lower] * downgradeHysteresis ? lower : current
    }

    private static func visibleSourceRect(
        cropRect: CGRect,
        nativeExtent: CGSize,
        cropSize: CGSize,
        transform: CanvasTransform,
        viewportSize: CGSize
    ) -> CGRect {
        guard isValidSize(nativeExtent), isValidSize(cropSize), isValidSize(viewportSize),
              transform.scale.isFinite, transform.scale > 0 else {
            return CGRect(origin: .zero, size: nativeExtent)
        }

        let visible = CGRect(
            x: (0 - transform.origin.x) / transform.scale,
            y: (0 - transform.origin.y) / transform.scale,
            width: viewportSize.width / transform.scale,
            height: viewportSize.height / transform.scale
        ).intersection(CGRect(origin: .zero, size: cropSize))
        guard !visible.isNull, visible.width > 0, visible.height > 0 else {
            return CGRect(origin: .zero, size: nativeExtent)
        }
        return CGRect(
            x: cropRect.minX * nativeExtent.width + visible.minX / cropSize.width * cropRect.width * nativeExtent.width,
            y: cropRect.minY * nativeExtent.height + visible.minY / cropSize.height * cropRect.height * nativeExtent.height,
            width: visible.width / cropSize.width * cropRect.width * nativeExtent.width,
            height: visible.height / cropSize.height * cropRect.height * nativeExtent.height
        )
    }

    private static func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
