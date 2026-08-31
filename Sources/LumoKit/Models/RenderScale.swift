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
    /// Native resolution.
    case full

    /// The maximum output box represented by this legacy scale, when one exists.
    var targetSize: CGSize? {
        switch self {
        case .preview(let maxSize): return maxSize
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
        }
    }
}
