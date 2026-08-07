import Foundation

/// One ordered tone/colour stage in an `EditDocument`.
///
/// **A closed enum, not `[any AdjustmentNode]`.** Protocol existentials cannot synthesize
/// `Equatable`/`Codable` and would need a hand-written type-tag coder — which would undermine the
/// value-state spine that earns undo and Swift 6 cleanliness in the first place. A closed enum is
/// equally ordered and composable, costs one case plus one switch arm to extend, and gets both
/// conformances free. See `docs/PHASE2_SPEC.md` §4.1.
///
/// **Order is meaningful.** `[.exposure(ev: 1), .colorControls(…)]` is not the same render as the
/// reverse, and duplicates are allowed (two exposure nodes stack). The array in `EditDocument` is a
/// pipeline, not a set of slots.
///
/// **Every case must use normalized units.** These five are inherently scale-invariant, which is what
/// lets a preview render early-downscaled and still match a full-resolution export. Any future
/// pixel-sized node — grain, blur, sharpen — **must** express its radius as a fraction of the image,
/// or preview and export diverge silently. See `docs/PHASE2_SPEC.md` §5.
enum AdjustmentNode: Codable, Sendable, Equatable {
    /// `CIExposureAdjust`. Identity at 0.
    case exposure(ev: Double)
    /// `CIColorControls`. Identity at (0, 1, 1) — the filter's own defaults.
    case colorControls(brightness: Double, contrast: Double, saturation: Double)
    /// `CIHighlightShadowAdjust`. Identity at (1, 0) — the filter's own defaults.
    case highlightShadow(highlights: Double, shadows: Double)
    /// `CITemperatureAndTint`. Identity at (6500, 0).
    ///
    /// The filter only sets `targetNeutral` against a fixed 6500 K source, so raising Kelvin *cools*
    /// the image, inverting the Lightroom convention (`docs/PHASE2_SPEC.md` §8.7, pinned by
    /// `testRaisingKelvinCoolsTheImage`). §8.7 is closed: rather than change this node's convention,
    /// the Adjust panel's slider is reflected about D65 in `AdjustmentControl.sliderMapped(_:)`.
    /// Identity at (6500, 0) holds either way, which is why it was a safe seed to define from the start.
    case temperatureTint(temp: Double, tint: Double)
    /// `CIVibrance`. Identity at 0.
    case vibrance(amount: Double)

    /// True when this node would leave the image untouched.
    ///
    /// The values below are the underlying `CIFilter` defaults, not a house convention — a node
    /// holding them is a genuine no-op, so the render can skip building the filter at all.
    var isIdentity: Bool {
        switch self {
        case .exposure(let ev):
            return ev == 0
        case .colorControls(let brightness, let contrast, let saturation):
            return brightness == 0 && contrast == 1 && saturation == 1
        case .highlightShadow(let highlights, let shadows):
            return highlights == 1 && shadows == 0
        case .temperatureTint(let temp, let tint):
            return temp == 6500 && tint == 0
        case .vibrance(let amount):
            return amount == 0
        }
    }

    /// A node of this kind that does nothing — the seed value an inspector control resets to.
    static let neutralExposure = AdjustmentNode.exposure(ev: 0)
    static let neutralColorControls = AdjustmentNode.colorControls(brightness: 0, contrast: 1, saturation: 1)
    static let neutralHighlightShadow = AdjustmentNode.highlightShadow(highlights: 1, shadows: 0)
    static let neutralTemperatureTint = AdjustmentNode.temperatureTint(temp: 6500, tint: 0)
    static let neutralVibrance = AdjustmentNode.vibrance(amount: 0)
}
