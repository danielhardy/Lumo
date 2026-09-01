import Foundation

/// The photographer-facing controls in the global Effects stage.
///
/// These enums keep the inspector's labels, ranges, and value mapping out of SwiftUI. The mapping
/// functions are pure so the sparse UI contract can be tested without constructing a view or a
/// renderer.
enum EffectsControl: String, CaseIterable, Hashable, Sendable {
    case texture, clarity, dehaze

    var title: String {
        switch self {
        case .texture: return "Texture"
        case .clarity: return "Clarity"
        case .dehaze: return "Dehaze"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .texture: return EffectsAdjustments.textureRange
        case .clarity: return EffectsAdjustments.clarityRange
        case .dehaze: return EffectsAdjustments.dehazeRange
        }
    }

    var neutral: Double { 0 }

    func value(in effects: EffectsAdjustments) -> Double {
        switch self {
        case .texture: return effects.texture
        case .clarity: return effects.clarity
        case .dehaze: return effects.dehaze
        }
    }

    func setting(_ value: Double, in effects: EffectsAdjustments) -> EffectsAdjustments {
        var updated = effects
        switch self {
        case .texture: updated.texture = value
        case .clarity: updated.clarity = value
        case .dehaze: updated.dehaze = value
        }
        return updated
    }
}

enum VignetteControl: String, CaseIterable, Hashable, Sendable {
    case amount, midpoint, roundness, feather, highlights

    var title: String { rawValue.capitalized }

    var range: ClosedRange<Double> {
        switch self {
        case .amount: return VignetteAdjustments.amountRange
        case .midpoint: return VignetteAdjustments.midpointRange
        case .roundness: return VignetteAdjustments.roundnessRange
        case .feather: return VignetteAdjustments.featherRange
        case .highlights: return VignetteAdjustments.highlightsRange
        }
    }

    var neutral: Double {
        switch self {
        case .amount: return 0
        case .midpoint: return 50
        case .roundness: return 0
        case .feather: return 50
        case .highlights: return 0
        }
    }

    func value(in vignette: VignetteAdjustments) -> Double {
        switch self {
        case .amount: return vignette.amount
        case .midpoint: return vignette.midpoint
        case .roundness: return vignette.roundness
        case .feather: return vignette.feather
        case .highlights: return vignette.highlights
        }
    }

    func setting(_ value: Double, in vignette: VignetteAdjustments) -> VignetteAdjustments {
        var updated = vignette
        switch self {
        case .amount: updated.amount = value
        case .midpoint: updated.midpoint = value
        case .roundness: updated.roundness = value
        case .feather: updated.feather = value
        case .highlights: updated.highlights = value
        }
        return updated
    }
}

enum GrainControl: String, CaseIterable, Hashable, Sendable {
    case amount, size, roughness

    var title: String { rawValue.capitalized }

    var range: ClosedRange<Double> {
        switch self {
        case .amount: return GrainAdjustments.amountRange
        case .size: return GrainAdjustments.sizeRange
        case .roughness: return GrainAdjustments.roughnessRange
        }
    }

    var neutral: Double {
        switch self {
        case .amount: return 0
        case .size: return 50
        case .roughness: return 50
        }
    }

    func value(in grain: GrainAdjustments) -> Double {
        switch self {
        case .amount: return grain.amount
        case .size: return grain.size
        case .roughness: return grain.roughness
        }
    }

    func setting(_ value: Double, in grain: GrainAdjustments) -> GrainAdjustments {
        var updated = grain
        switch self {
        case .amount: updated.amount = value
        case .size: updated.size = value
        case .roughness: updated.roughness = value
        }
        return updated
    }
}
