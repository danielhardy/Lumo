import Foundation

/// Photographer-facing global colour controls.
///
/// Values use the same -100...100 scale shown by the Color inspector, rather than Core Image's
/// filter parameters. Keeping that conversion at the render boundary makes persisted edits stable
/// if the implementation changes and gives preview and export one normalization rule. Mixer and
/// grading state can be added to this value without changing the document's top-level colour stage.
struct ColorAdjustments: Codable, Equatable, Sendable {
    static let neutral = ColorAdjustments()

    static let vibranceRange = -100.0...100.0
    static let saturationRange = -100.0...100.0

    var vibrance: Double {
        didSet { vibrance = Self.clamp(vibrance, to: Self.vibranceRange, default: 0) }
    }
    var saturation: Double {
        didSet { saturation = Self.clamp(saturation, to: Self.saturationRange, default: 0) }
    }
    var mixer: ColorMixerAdjustments

    init(
        vibrance: Double = 0,
        saturation: Double = 0,
        mixer: ColorMixerAdjustments = .neutral
    ) {
        self.vibrance = Self.clamp(vibrance, to: Self.vibranceRange, default: 0)
        self.saturation = Self.clamp(saturation, to: Self.saturationRange, default: 0)
        self.mixer = mixer
    }

    var isIdentity: Bool { vibrance == 0 && saturation == 0 && mixer.isIdentity }

    /// `CIVibrance.inputAmount` is normalized to -1...1.
    var normalizedVibrance: Double { vibrance / 100 }

    /// `CIColorControls.inputSaturation` is a multiplier whose identity is 1.
    /// Therefore -100 is exactly zero saturation and +100 is 2× saturation.
    var normalizedSaturation: Double { 1 + saturation / 100 }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        default fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey { case vibrance, saturation, mixer }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            vibrance: try container.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0,
            saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            mixer: try container.decodeIfPresent(ColorMixerAdjustments.self, forKey: .mixer) ?? .neutral
        )
    }
}
