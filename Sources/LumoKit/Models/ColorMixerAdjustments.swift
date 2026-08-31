import Foundation

/// The three photographer-facing controls for one HSL colour neighborhood.
///
/// Values use the familiar -100...100 scale. Hue is converted to a small angular move by the
/// renderer; Saturation and Luminance are fractional changes to the pixel's HSL components. The
/// model deliberately contains no Core Image types, so it is safe to persist, hash, undo, and
/// send across the render boundary.
struct ColorMixerChannel: Codable, Equatable, Sendable {
    static let hueRange = -100.0...100.0
    static let saturationRange = -100.0...100.0
    static let luminanceRange = -100.0...100.0

    var hue: Double {
        didSet { hue = Self.clamp(hue, to: Self.hueRange, default: 0) }
    }
    var saturation: Double {
        didSet { saturation = Self.clamp(saturation, to: Self.saturationRange, default: 0) }
    }
    var luminance: Double {
        didSet { luminance = Self.clamp(luminance, to: Self.luminanceRange, default: 0) }
    }

    static let neutral = ColorMixerChannel()

    init(hue: Double = 0, saturation: Double = 0, luminance: Double = 0) {
        self.hue = Self.clamp(hue, to: Self.hueRange, default: 0)
        self.saturation = Self.clamp(saturation, to: Self.saturationRange, default: 0)
        self.luminance = Self.clamp(luminance, to: Self.luminanceRange, default: 0)
    }

    var isIdentity: Bool { hue == 0 && saturation == 0 && luminance == 0 }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        default fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey { case hue, saturation, luminance }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hue: try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0,
            saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            luminance: try container.decodeIfPresent(Double.self, forKey: .luminance) ?? 0
        )
    }
}

/// Eight fixed HSL neighborhoods in the order used by the Color Mixer UI and renderer.
///
/// The explicit properties make the persisted JSON readable and stable. `channels` is only a
/// convenience for tests and future UI construction; rendering receives the fixed values directly
/// and never performs a per-pixel Swift loop.
struct ColorMixerAdjustments: Codable, Equatable, Sendable {
    static let neutral = ColorMixerAdjustments()

    var red: ColorMixerChannel
    var orange: ColorMixerChannel
    var yellow: ColorMixerChannel
    var green: ColorMixerChannel
    var aqua: ColorMixerChannel
    var blue: ColorMixerChannel
    var purple: ColorMixerChannel
    var magenta: ColorMixerChannel

    init(
        red: ColorMixerChannel = .neutral,
        orange: ColorMixerChannel = .neutral,
        yellow: ColorMixerChannel = .neutral,
        green: ColorMixerChannel = .neutral,
        aqua: ColorMixerChannel = .neutral,
        blue: ColorMixerChannel = .neutral,
        purple: ColorMixerChannel = .neutral,
        magenta: ColorMixerChannel = .neutral
    ) {
        self.red = red
        self.orange = orange
        self.yellow = yellow
        self.green = green
        self.aqua = aqua
        self.blue = blue
        self.purple = purple
        self.magenta = magenta
    }

    var channels: [ColorMixerChannel] {
        [red, orange, yellow, green, aqua, blue, purple, magenta]
    }

    var isIdentity: Bool { channels.allSatisfy(\.isIdentity) }

    private enum CodingKeys: String, CodingKey {
        case red, orange, yellow, green, aqua, blue, purple, magenta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decodeIfPresent(ColorMixerChannel.self, forKey: .red) ?? .neutral,
            orange: try container.decodeIfPresent(ColorMixerChannel.self, forKey: .orange) ?? .neutral,
            yellow: try container.decodeIfPresent(ColorMixerChannel.self, forKey: .yellow) ?? .neutral,
            green: try container.decodeIfPresent(ColorMixerChannel.self, forKey: .green) ?? .neutral,
            aqua: try container.decodeIfPresent(ColorMixerChannel.self, forKey: .aqua) ?? .neutral,
            blue: try container.decodeIfPresent(ColorMixerChannel.self, forKey: .blue) ?? .neutral,
            purple: try container.decodeIfPresent(ColorMixerChannel.self, forKey: .purple) ?? .neutral,
            magenta: try container.decodeIfPresent(ColorMixerChannel.self, forKey: .magenta) ?? .neutral
        )
    }
}

/// Compatibility spellings for callers that describe the value as a channel adjustment.
typealias ColorMixerChannelAdjustment = ColorMixerChannel
typealias ColorMixerChannelAdjustments = ColorMixerChannel
