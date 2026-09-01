import Foundation
import CoreGraphics

/// The one thing that differs between a preview and an export.
///
/// Preview/export parity is structural in Phase 2 rather than a pair of code paths that merely agree:
/// both call the same `buildImage`, and this value is the only argument that changes. See
/// `docs/PHASE2_SPEC.md` §1.
///
/// The scale is applied **early** — `CIRAWFilter.scaleFactor` before `outputImage` for RAW, a Lanczos
/// step right after load for standard images — so adjustment and LUT nodes operate on a preview-sized
/// image rather than the full extent. That is what makes every `AdjustmentNode`'s
/// resolution-independence a hard requirement rather than a nicety (§5).
enum RenderScale: Sendable, Equatable {
    /// Fit within `maxSize`, never upscaling.
    case preview(maxSize: CGSize)
    /// Interaction policy. The input is the canvas backing-pixel size, not a fixed export box.
    /// Interactive rendering intentionally uses a bounded pixel budget so a large RAW cannot
    /// monopolize the GPU past the next display tick.
    case interactive(maxSize: CGSize, frameBudgetMilliseconds: Double = 16.7)
    /// Native resolution.
    case full

    var isFull: Bool {
        if case .full = self { return true }
        return false
    }

    /// The maximum output box represented by this legacy scale, when one exists.
    var targetSize: CGSize? {
        switch self {
        case .preview(let maxSize): return maxSize
        case .interactive(let maxSize, let budget):
            let safeBudget = budget.isFinite && budget > 0 ? budget : 16.7
            // The 1.5 MP cap is the interaction budget calibrated against the existing preview
            // benchmark. Scale it by the requested frame budget, while always respecting the
            // actual drawable size and never upscaling.
            let budgetPixels = 1_500_000.0 * safeBudget / 16.7
            guard maxSize.width > 0, maxSize.height > 0,
                  maxSize.width.isFinite, maxSize.height.isFinite else { return maxSize }
            let pixels = maxSize.width * maxSize.height
            guard pixels > budgetPixels else { return maxSize }
            let factor = sqrt(budgetPixels / pixels)
            return CGSize(width: maxSize.width * factor, height: maxSize.height * factor)
        case .full: return nil
        }
    }

    /// The factor to render `nativeExtent` at, in 0…1.
    ///
    /// Always ≤ 1: a preview box larger than the image renders at 1.0 rather than magnifying it.
    /// Degenerate inputs (a zero or non-finite extent, an empty preview box) fall back to 1.0, which
    /// leaves the source alone and lets the caller's own extent check reject it — rather than
    /// producing a zero or NaN scale that would trap later on when it reaches `Int(width)`.
    func factor(for nativeExtent: CGSize) -> CGFloat {
        switch self {
        case .full:
            return 1.0
        case .preview(let maxSize):
            guard nativeExtent.width > 0, nativeExtent.height > 0,
                  nativeExtent.width.isFinite, nativeExtent.height.isFinite,
                  maxSize.width > 0, maxSize.height > 0
            else { return 1.0 }
            return min(maxSize.width / nativeExtent.width, maxSize.height / nativeExtent.height, 1.0)
        case .interactive:
            // `targetSize` applies the interactive pixel budget. Using the unbounded drawable
            // size here made the cap advisory only: RAW development still ran at the full backing
            // resolution, so a rapid curve drag could fill the presentation queue.
            guard let maxSize = targetSize,
                  nativeExtent.width > 0, nativeExtent.height > 0,
                  nativeExtent.width.isFinite, nativeExtent.height.isFinite,
                  maxSize.width > 0, maxSize.height > 0
            else { return 1.0 }
            return min(maxSize.width / nativeExtent.width, maxSize.height / nativeExtent.height, 1.0)
        }
    }
}
