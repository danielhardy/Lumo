import Foundation

/// The hue and saturation of one three-way color-grading wheel.
///
/// Hue is expressed in degrees around the wheel and saturation uses the photographer-facing
/// 0...100 scale. A hue without saturation has no visual meaning, so it is intentionally treated as
/// identity. That keeps a wheel's position independent from whether its color amount is enabled.
struct ColorGradingWheel: Codable, Equatable, Sendable {
    static let hueRange = 0.0...360.0
    static let saturationRange = 0.0...100.0

    var hue: Double {
        didSet { hue = Self.clamp(hue, to: Self.hueRange, default: 0) }
    }
    var saturation: Double {
        didSet { saturation = Self.clamp(saturation, to: Self.saturationRange, default: 0) }
    }

    static let neutral = ColorGradingWheel()

    init(hue: Double = 0, saturation: Double = 0) {
        self.hue = Self.clamp(hue, to: Self.hueRange, default: 0)
        self.saturation = Self.clamp(saturation, to: Self.saturationRange, default: 0)
    }

    /// Hue is deliberately omitted: a wheel at zero saturation is an exact no-op for any hue.
    var isIdentity: Bool { saturation == 0 }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        default fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey { case hue, saturation }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hue: try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0,
            saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        )
    }
}

/// A point on a grading wheel, with its center at `(0, 0)` and its rim one unit away.
///
/// Keeping the interaction mapping in the model layer makes the wheel's behaviour independent of
/// SwiftUI layout and lets the same conversion be regression-tested without synthesising a drag.
struct ColorGradingWheelPoint: Equatable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Converts between a visual wheel position and the persisted hue/saturation representation.
///
/// The positive x axis is 0°, and the positive y axis is 90° (the view flips AppKit's downward y
/// coordinate before calling this type). Positions beyond the rim retain their direction and clamp
/// to 100% saturation, so a drag can always reach the edge without a discontinuity.
enum ColorGradingWheelMapping {
    static let accessibilityStep = 5.0

    static func wheel(at point: ColorGradingWheelPoint) -> ColorGradingWheel {
        let distance = hypot(point.x, point.y)
        guard distance > 0 else { return .neutral }

        let degrees = atan2(point.y, point.x) * 180 / .pi
        let hue = degrees < 0 ? degrees + 360 : degrees
        return ColorGradingWheel(hue: hue, saturation: min(distance, 1) * 100)
    }

    static func point(for wheel: ColorGradingWheel) -> ColorGradingWheelPoint {
        let radius = wheel.saturation / 100
        let radians = wheel.hue * .pi / 180
        return ColorGradingWheelPoint(x: cos(radians) * radius, y: sin(radians) * radius)
    }

    static func adjustingSaturation(_ wheel: ColorGradingWheel, by amount: Double) -> ColorGradingWheel {
        ColorGradingWheel(hue: wheel.hue, saturation: wheel.saturation + amount)
    }

    static func accessibilityValue(for wheel: ColorGradingWheel) -> String {
        "Hue \(Int(wheel.hue.rounded())) degrees, Saturation \(Int(wheel.saturation.rounded())) percent"
    }
}

/// Shadows, midtones, and highlights color grading controls.
///
/// Blending widens the smooth overlap between tonal regions. Balance shifts the tonal center
/// toward shadows (negative) or highlights (positive). Neither control changes pixels when all
/// three wheel saturations are zero, which makes the neutral value an exact render identity.
struct ColorGradingAdjustments: Codable, Equatable, Sendable {
    static let blendingRange = 0.0...100.0
    static let balanceRange = -100.0...100.0

    static let neutral = ColorGradingAdjustments()

    var shadows: ColorGradingWheel
    var midtones: ColorGradingWheel
    var highlights: ColorGradingWheel

    /// 0 is the narrowest separation and 100 gives the widest tonal overlap.
    var blending: Double {
        didSet { blending = Self.clamp(blending, to: Self.blendingRange, default: 50) }
    }

    /// Negative values favor shadows; positive values favor highlights.
    var balance: Double {
        didSet { balance = Self.clamp(balance, to: Self.balanceRange, default: 0) }
    }

    init(
        shadows: ColorGradingWheel = .neutral,
        midtones: ColorGradingWheel = .neutral,
        highlights: ColorGradingWheel = .neutral,
        blending: Double = 50,
        balance: Double = 0
    ) {
        self.shadows = shadows
        self.midtones = midtones
        self.highlights = highlights
        self.blending = Self.clamp(blending, to: Self.blendingRange, default: 50)
        self.balance = Self.clamp(balance, to: Self.balanceRange, default: 0)
    }

    /// Blending and balance are only weighting controls; without wheel saturation they cannot
    /// change a pixel and therefore do not prevent the grading stage from being skipped.
    var isIdentity: Bool {
        shadows.isIdentity && midtones.isIdentity && highlights.isIdentity
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        default fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey { case shadows, midtones, highlights, blending, balance }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shadows: try container.decodeIfPresent(ColorGradingWheel.self, forKey: .shadows) ?? .neutral,
            midtones: try container.decodeIfPresent(ColorGradingWheel.self, forKey: .midtones) ?? .neutral,
            highlights: try container.decodeIfPresent(ColorGradingWheel.self, forKey: .highlights) ?? .neutral,
            blending: try container.decodeIfPresent(Double.self, forKey: .blending) ?? 50,
            balance: try container.decodeIfPresent(Double.self, forKey: .balance) ?? 0
        )
    }
}
