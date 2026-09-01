import Foundation

/// Photographer-facing global Effects controls.
///
/// The three controls deliberately share a -100...100 scale but not an operation. Texture is a
/// small-radius detail operation, Clarity is a larger-radius operation limited to midtones, and
/// Dehaze combines local contrast with tonal and colour separation. The renderer owns the mapping
/// from these values to Core Image filters; keeping that mapping out of the persisted value makes
/// the edit portable across preview and export resolutions.
struct EffectsAdjustments: Codable, Equatable, Sendable {
    static let neutral = EffectsAdjustments()

    static let textureRange = -100.0...100.0
    static let clarityRange = -100.0...100.0
    static let dehazeRange = -100.0...100.0

    var texture: Double {
        didSet { texture = Self.clamp(texture, to: Self.textureRange, default: 0) }
    }
    var clarity: Double {
        didSet { clarity = Self.clamp(clarity, to: Self.clarityRange, default: 0) }
    }
    var dehaze: Double {
        didSet { dehaze = Self.clamp(dehaze, to: Self.dehazeRange, default: 0) }
    }

    init(texture: Double = 0, clarity: Double = 0, dehaze: Double = 0) {
        self.texture = Self.clamp(texture, to: Self.textureRange, default: 0)
        self.clarity = Self.clamp(clarity, to: Self.clarityRange, default: 0)
        self.dehaze = Self.clamp(dehaze, to: Self.dehazeRange, default: 0)
    }

    var isIdentity: Bool { texture == 0 && clarity == 0 && dehaze == 0 }

    private enum CodingKeys: String, CodingKey { case texture, clarity, dehaze }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            texture: try container.decodeIfPresent(Double.self, forKey: .texture) ?? 0,
            clarity: try container.decodeIfPresent(Double.self, forKey: .clarity) ?? 0,
            dehaze: try container.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0
        )
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        default fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
