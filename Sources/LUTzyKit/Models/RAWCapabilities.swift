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

    /// True when this control is a toggle rather than a slider.
    ///
    /// **No `default:` arm, deliberately.** This used to live on `AppViewModel` and end in
    /// `default: return false`, so an eighteenth `DevelopControl` would silently have become a
    /// slider — and a `Bool` knob driven by a slider writes 0.37 into a checkbox. Enumerated in full,
    /// adding a case is a compile error that names the file to edit.
    var isToggle: Bool {
        switch self {
        case .lensCorrection, .gamutMapping, .highlightRecovery:
            return true
        case .exposure, .baselineExposure, .shadowBias, .boost, .boostShadow, .whiteBalance,
             .sharpness, .contrast, .detail, .moireReduction, .localToneMap,
             .luminanceNoiseReduction, .colorNoiseReduction, .extendedDynamicRange:
            return false
        }
    }

    /// The slider range for a control.
    ///
    /// Lives beside `RAWDevelopSettings` rather than on the view model because it is a pure function
    /// of the case, and because keeping the literals one file away from the doc comments they must
    /// match is what lets `RAWCapabilitiesTests` check the two against each other.
    ///
    /// **Which of these are documented, and which are ours.** Documented — by `CIRAWFilter`, recorded
    /// in `RAWDevelopSettings`' per-property comments and `PHASE2_SPEC.md` §9: `boost` 0…1,
    /// `boostShadow` 0…2, `whiteBalance` 2000…50000 K, tint −150…150, `detail` 0…3,
    /// `extendedDynamicRange` 0…2, and the 0…1 detail amounts (sharpness, contrast, moiré, local tone
    /// map, both noise reductions). **Chosen by us**, with no documented bound anywhere in the repo or
    /// the header: `exposure` and `baselineExposure` at −4…4, and `shadowBias` at −10…10. Those three
    /// are UI conveniences — a usable throw for a slider — not framework limits, and `CIRAWFilter`
    /// will accept values outside them. Widen them freely; the other rows are not ours to move.
    ///
    /// **These three are observational, not documented — one camera's worth of data.** Probed directly
    /// off a fresh `CIRAWFilter(imageURL:)` for the Leica M11 DNG in `realworldtest/` (no date attached
    /// to the file; the camera is the only fact worth recording): `exposure` reads **0.0**, comfortably
    /// centred in −4…4 — checked, not assumed, and left unchanged. `baselineExposure` reads **0.4**,
    /// also comfortably inside −4…4 — checked and left unchanged. `shadowBias` reads **5.0**, which the
    /// previous −1…1 range didn't even contain: that slider opened pinned at its maximum on this
    /// camera and could only be dragged down. `shadowBias` is now −10…10 — round, symmetric like the
    /// other two, and puts 5.0 well clear of either edge (5 of headroom above, 15 below) rather than
    /// pinned. `RAWCapabilitiesTests.testProbingARealRAWReportsItsDecodersSeeds` re-measures the same
    /// three each time a real DNG is available and prints them, and
    /// `testEveryPerImageSeedLandsStrictlyInsideItsSliderRange` asserts every per-image seed sits
    /// strictly inside its control's range — the check that would have caught this. With a sample size
    /// of one camera, "comfortable" is a judgement call, not a proof; widen further the moment a second
    /// camera disagrees.
    ///
    /// **`boost` and `boostShadow` are not the same range**, despite the plan's draft grouping them:
    /// `boostAmount`'s own doc comment (`RAWDevelopSettings.swift`) is explicit — "Global tone curve,
    /// 0…1" — while `boostShadowAmount` is "0…2 (<1 darkens, >1 lightens)". Sharing one case would
    /// let the boost slider reach 2.0, a value outside what `CIRAWFilter` documents for that knob.
    ///
    /// No `default:` arm here either, for the reason given on `isToggle`: the old one handed every
    /// unlisted case a 0…1 slider, which is exactly how a mis-grouped `boostShadow` would have gone
    /// unnoticed.
    var range: ClosedRange<Double> {
        switch self {
        case .exposure, .baselineExposure: return -4...4
        case .shadowBias: return -10...10
        case .boost: return 0...1
        case .boostShadow: return 0...2
        case .whiteBalance: return 2000...50000
        case .detail: return 0...3
        case .extendedDynamicRange: return 0...2
        case .sharpness, .contrast, .moireReduction, .localToneMap,
             .luminanceNoiseReduction, .colorNoiseReduction: return 0...1
        case .lensCorrection, .gamutMapping, .highlightRecovery: return 0...1
        }
    }

    /// The tint slider's range. One row, two sliders — see `AppViewModel.developTintBinding()`.
    /// Documented by `CIRAWFilter` as −150…150.
    static let tintRange: ClosedRange<Double> = -150...150
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

    /// The eight below are the *gated* seeds: each is only meaningful when its `is*Supported`
    /// neighbour is true, and `RenderEngine.rawCapabilities(for:)` reads each one only then. Asking a
    /// decoder for a sharpening amount it does not offer answers nothing, so the value stays at the
    /// default below rather than recording whatever the unsupported property happens to return.
    ///
    /// They exist for the same reason `baselineExposure` does. `RAWDevelopSettings`' own type doc is
    /// explicit that the noise-reduction and sharpening defaults **vary per image**, so a slider bound
    /// to one of these while its setting is `nil` has nothing to display without a seed — and a
    /// guessed `0` means the control opens in the wrong place and the first nudge jumps the picture.
    var sharpnessAmount: Double
    var contrastAmount: Double
    var detailAmount: Double
    var moireReductionAmount: Double
    var localToneMapAmount: Double
    var luminanceNoiseReductionAmount: Double
    var colorNoiseReductionAmount: Double
    var lensCorrectionEnabled: Bool

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
        shadowBias: Double = 0,
        sharpnessAmount: Double = 0,
        contrastAmount: Double = 0,
        detailAmount: Double = 0,
        moireReductionAmount: Double = 0,
        localToneMapAmount: Double = 0,
        luminanceNoiseReductionAmount: Double = 0,
        colorNoiseReductionAmount: Double = 0,
        lensCorrectionEnabled: Bool = false
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
        self.sharpnessAmount = sharpnessAmount
        self.contrastAmount = contrastAmount
        self.detailAmount = detailAmount
        self.moireReductionAmount = moireReductionAmount
        self.localToneMapAmount = localToneMapAmount
        self.luminanceNoiseReductionAmount = luminanceNoiseReductionAmount
        self.colorNoiseReductionAmount = colorNoiseReductionAmount
        self.lensCorrectionEnabled = lensCorrectionEnabled
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
