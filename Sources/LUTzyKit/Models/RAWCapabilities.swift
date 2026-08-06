import Foundation

/// One knob in the develop panel.
///
/// A value rather than a set of `if`s in a `ViewBuilder`, so which controls a given file offers can
/// be asserted without instantiating a view — this repo has no SwiftUI view tests. The declaration
/// order below **is** the panel's layout order.
enum DevelopControl: String, Sendable, CaseIterable {
    case exposure
    case baselineExposure
    case shadowBias
    case boost
    case boostShadow
    case whiteBalance
    case sharpness
    case contrast
    case detail
    case moireReduction
    case localToneMap
    case luminanceNoiseReduction
    case colorNoiseReduction
    case lensCorrection
    case gamutMapping
    case extendedDynamicRange
    case highlightRecovery

    var title: String {
        switch self {
        case .exposure: return "Exposure"
        case .baselineExposure: return "Baseline Exposure"
        case .shadowBias: return "Shadow Bias"
        case .boost: return "Boost"
        case .boostShadow: return "Boost Shadows"
        case .whiteBalance: return "White Balance"
        case .sharpness: return "Sharpness"
        case .contrast: return "Local Contrast"
        case .detail: return "Detail"
        case .moireReduction: return "Moiré Reduction"
        case .localToneMap: return "Local Tone Map"
        case .luminanceNoiseReduction: return "Luminance NR"
        case .colorNoiseReduction: return "Colour NR"
        case .lensCorrection: return "Lens Correction"
        case .gamutMapping: return "Gamut Mapping"
        case .extendedDynamicRange: return "Extended Dynamic Range"
        case .highlightRecovery: return "Highlight Recovery"
        }
    }
}

/// What one particular RAW file's decoder can do, and where its own defaults sit.
///
/// **Why this type exists.** `CIRAWFilter` exposes an `is*Supported` flag per adjustment, and writing
/// to an unsupported one is at best ignored — `RAWDevelopSettings.apply(to:)` already honours that.
/// But `CIRAWFilter` is not `Sendable` and lives inside `actor RenderEngine` (`PHASE2_SPEC.md` §4.5),
/// so a `@MainActor` inspector cannot read those flags. This is the value that crosses the boundary.
///
/// **It carries seeds as well as flags, and that is not padding.** Every `RAWDevelopSettings`
/// property is `Optional` with `nil` meaning "leave the decoder at its default", and several of those
/// defaults *vary per image* — as-shot white balance on the Leica in `realworldtest/` is
/// 5842.2 K / 14.04, not a round number. A slider bound to a `nil` setting has nothing to display
/// without these.
struct RAWCapabilities: Sendable, Equatable {

    // MARK: - Gates

    var isSharpnessSupported: Bool
    var isContrastSupported: Bool
    var isDetailSupported: Bool
    var isMoireReductionSupported: Bool
    var isLocalToneMapSupported: Bool
    var isLuminanceNoiseReductionSupported: Bool
    var isColorNoiseReductionSupported: Bool
    var isLensCorrectionSupported: Bool
    /// Always false below macOS 26, where the property is not in the imported interface at all.
    var isHighlightRecoverySupported: Bool

    // MARK: - Per-image seeds

    var asShotTemperature: Double
    var asShotTint: Double
    var baselineExposure: Double
    var shadowBias: Double

    init(
        isSharpnessSupported: Bool = false,
        isContrastSupported: Bool = false,
        isDetailSupported: Bool = false,
        isMoireReductionSupported: Bool = false,
        isLocalToneMapSupported: Bool = false,
        isLuminanceNoiseReductionSupported: Bool = false,
        isColorNoiseReductionSupported: Bool = false,
        isLensCorrectionSupported: Bool = false,
        isHighlightRecoverySupported: Bool = false,
        asShotTemperature: Double = 0,
        asShotTint: Double = 0,
        baselineExposure: Double = 0,
        shadowBias: Double = 0
    ) {
        self.isSharpnessSupported = isSharpnessSupported
        self.isContrastSupported = isContrastSupported
        self.isDetailSupported = isDetailSupported
        self.isMoireReductionSupported = isMoireReductionSupported
        self.isLocalToneMapSupported = isLocalToneMapSupported
        self.isLuminanceNoiseReductionSupported = isLuminanceNoiseReductionSupported
        self.isColorNoiseReductionSupported = isColorNoiseReductionSupported
        self.isLensCorrectionSupported = isLensCorrectionSupported
        self.isHighlightRecoverySupported = isHighlightRecoverySupported
        self.asShotTemperature = asShotTemperature
        self.asShotTint = asShotTint
        self.baselineExposure = baselineExposure
        self.shadowBias = shadowBias
    }

    /// A decoder that refuses nothing. For tests, and for reasoning about the upper bound.
    static let everythingSupported = RAWCapabilities(
        isSharpnessSupported: true,
        isContrastSupported: true,
        isDetailSupported: true,
        isMoireReductionSupported: true,
        isLocalToneMapSupported: true,
        isLuminanceNoiseReductionSupported: true,
        isColorNoiseReductionSupported: true,
        isLensCorrectionSupported: true,
        isHighlightRecoverySupported: true
    )

    /// Whether this file's decoder offers `control`.
    func supports(_ control: DevelopControl) -> Bool {
        switch control {
        case .exposure, .baselineExposure, .shadowBias, .boost, .boostShadow,
             .whiteBalance, .gamutMapping, .extendedDynamicRange:
            // Ungated: `RAWDevelopSettings.apply(to:)` writes these for every decodable RAW.
            return true
        case .sharpness: return isSharpnessSupported
        case .contrast: return isContrastSupported
        case .detail: return isDetailSupported
        case .moireReduction: return isMoireReductionSupported
        case .localToneMap: return isLocalToneMapSupported
        case .luminanceNoiseReduction: return isLuminanceNoiseReductionSupported
        case .colorNoiseReduction: return isColorNoiseReductionSupported
        case .lensCorrection: return isLensCorrectionSupported
        case .highlightRecovery: return isHighlightRecoverySupported
        }
    }

    /// The controls to draw, in panel order.
    ///
    /// An unsupported control is **omitted, not disabled**: a greyed-out slider invites the user to
    /// wonder what they did wrong, where absence reads correctly as "this camera's decoder does not
    /// do that".
    var availableControls: [DevelopControl] {
        DevelopControl.allCases.filter(supports)
    }
}
