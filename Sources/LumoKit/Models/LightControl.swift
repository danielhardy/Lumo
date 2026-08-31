import Foundation

/// The photographer-facing rows in the Light inspector.
///
/// Keeping this list as data makes the UI order, labels, neutral values, and ranges testable
/// without constructing SwiftUI views or exposing Core Image terminology to the inspector.
enum LightControl: String, CaseIterable, Hashable, Sendable {
    case exposure, contrast, highlights, shadows, whites, blacks

    var title: String {
        switch self {
        case .exposure: return "Exposure"
        case .contrast: return "Contrast"
        case .highlights: return "Highlights"
        case .shadows: return "Shadows"
        case .whites: return "Whites"
        case .blacks: return "Blacks"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure: return LightAdjustments.exposureRange
        case .contrast: return LightAdjustments.contrastRange
        case .highlights: return LightAdjustments.highlightsRange
        case .shadows: return LightAdjustments.shadowsRange
        case .whites: return LightAdjustments.whitesRange
        case .blacks: return LightAdjustments.blacksRange
        }
    }

    var neutral: Double { 0 }

    func value(in light: LightAdjustments) -> Double {
        switch self {
        case .exposure: return light.exposure
        case .contrast: return light.contrast
        case .highlights: return light.highlights
        case .shadows: return light.shadows
        case .whites: return light.whites
        case .blacks: return light.blacks
        }
    }

    func setting(_ value: Double, in light: inout LightAdjustments) {
        switch self {
        case .exposure: light.exposure = value
        case .contrast: light.contrast = value
        case .highlights: light.highlights = value
        case .shadows: light.shadows = value
        case .whites: light.whites = value
        case .blacks: light.blacks = value
        }
    }
}
