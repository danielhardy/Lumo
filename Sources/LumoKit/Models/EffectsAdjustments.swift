import Foundation

/// Photographer-facing controls for the post-crop vignette.
///
/// The renderer maps these normalized values to a mask over the image extent it receives. The
/// extent is therefore the post-crop/output geometry, rather than the source image geometry, and
/// the same values produce the same composition in preview and export.
struct VignetteAdjustments: Codable, Equatable, Sendable {
    static let neutral = VignetteAdjustments()

    static let amountRange = -100.0...100.0
    static let midpointRange = 0.0...100.0
    static let roundnessRange = -100.0...100.0
    static let featherRange = 0.0...100.0
    static let highlightsRange = 0.0...100.0

    /// Negative values brighten the edges; positive values darken them.
    var amount: Double {
        didSet { amount = Self.clamp(amount, to: Self.amountRange, default: 0) }
    }
    /// The normalized radius where the vignette starts. Lower values reach farther into the frame.
    var midpoint: Double {
        didSet { midpoint = Self.clamp(midpoint, to: Self.midpointRange, default: 50) }
    }
    /// Negative values are more rectangular; positive values are rounder.
    var roundness: Double {
        didSet { roundness = Self.clamp(roundness, to: Self.roundnessRange, default: 0) }
    }
    /// Width of the transition from the midpoint to the frame edge.
    var feather: Double {
        didSet { feather = Self.clamp(feather, to: Self.featherRange, default: 50) }
    }
    /// Reduces the vignette over bright pixels, preserving specular/highlight detail.
    var highlights: Double {
        didSet { highlights = Self.clamp(highlights, to: Self.highlightsRange, default: 0) }
    }

    init(
        amount: Double = 0,
        midpoint: Double = 50,
        roundness: Double = 0,
        feather: Double = 50,
        highlights: Double = 0
    ) {
        self.amount = Self.clamp(amount, to: Self.amountRange, default: 0)
        self.midpoint = Self.clamp(midpoint, to: Self.midpointRange, default: 50)
        self.roundness = Self.clamp(roundness, to: Self.roundnessRange, default: 0)
        self.feather = Self.clamp(feather, to: Self.featherRange, default: 50)
        self.highlights = Self.clamp(highlights, to: Self.highlightsRange, default: 0)
    }

    /// Only Amount can turn the operation on. Subordinate values remain persisted at neutral
    /// Amount so the shape can be previewed again without being lost.
    var isIdentity: Bool { amount == 0 }

    private enum CodingKeys: String, CodingKey { case amount, midpoint, roundness, feather, highlights }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            amount: try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0,
            midpoint: try container.decodeIfPresent(Double.self, forKey: .midpoint) ?? 50,
            roundness: try container.decodeIfPresent(Double.self, forKey: .roundness) ?? 0,
            feather: try container.decodeIfPresent(Double.self, forKey: .feather) ?? 50,
            highlights: try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
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

/// Photographer-facing film grain controls.
///
/// Grain Amount is the only control that enables the operation. Size and Roughness remain
/// persisted while Amount is zero so a grain recipe can be switched off and on without losing its
/// shape. The renderer maps Size to a frequency relative to the output's shortest side.
struct GrainAdjustments: Codable, Equatable, Sendable {
    static let neutral = GrainAdjustments()

    static let amountRange = 0.0...100.0
    static let sizeRange = 0.0...100.0
    static let roughnessRange = 0.0...100.0

    var amount: Double {
        didSet { amount = Self.clamp(amount, to: Self.amountRange, default: 0) }
    }
    /// Small values produce finer grain; large values produce larger photographic clumps.
    var size: Double {
        didSet { size = Self.clamp(size, to: Self.sizeRange, default: 50) }
    }
    /// Low values favor soft, clustered grain; high values add finer variation within each clump.
    var roughness: Double {
        didSet { roughness = Self.clamp(roughness, to: Self.roughnessRange, default: 50) }
    }

    init(amount: Double = 0, size: Double = 50, roughness: Double = 50) {
        self.amount = Self.clamp(amount, to: Self.amountRange, default: 0)
        self.size = Self.clamp(size, to: Self.sizeRange, default: 50)
        self.roughness = Self.clamp(roughness, to: Self.roughnessRange, default: 50)
    }

    var isIdentity: Bool { amount == 0 }

    private enum CodingKeys: String, CodingKey { case amount, size, roughness }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            amount: try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0,
            size: try container.decodeIfPresent(Double.self, forKey: .size) ?? 50,
            roughness: try container.decodeIfPresent(Double.self, forKey: .roughness) ?? 50
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

/// Photographer-facing global Effects controls.
///
/// The three main controls deliberately share a -100...100 scale but not an operation. Texture is a
/// small-radius detail operation, Clarity is a larger-radius operation limited to midtones, and
/// Dehaze combines local contrast with tonal and colour separation. Vignette and Grain are nested
/// parameter groups. The renderer owns the mapping from these values to Core Image filters;
/// keeping that mapping out of the persisted value makes the edit portable across preview and
/// export resolutions.
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
    var vignette: VignetteAdjustments
    /// Post-LUT film grain. Amount is the identity gate; Size and Roughness remain persisted while
    /// Amount is zero.
    var grain: GrainAdjustments

    init(
        texture: Double = 0,
        clarity: Double = 0,
        dehaze: Double = 0,
        vignette: VignetteAdjustments = .neutral,
        grain: GrainAdjustments = .neutral
    ) {
        self.texture = Self.clamp(texture, to: Self.textureRange, default: 0)
        self.clarity = Self.clamp(clarity, to: Self.clarityRange, default: 0)
        self.dehaze = Self.clamp(dehaze, to: Self.dehazeRange, default: 0)
        self.vignette = vignette
        self.grain = grain
    }

    var isIdentity: Bool {
        texture == 0 && clarity == 0 && dehaze == 0 && vignette.isIdentity && grain.isIdentity
    }

    private enum CodingKeys: String, CodingKey { case texture, clarity, dehaze, vignette, grain }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            texture: try container.decodeIfPresent(Double.self, forKey: .texture) ?? 0,
            clarity: try container.decodeIfPresent(Double.self, forKey: .clarity) ?? 0,
            dehaze: try container.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0,
            vignette: try container.decodeIfPresent(VignetteAdjustments.self, forKey: .vignette) ?? .neutral,
            grain: try container.decodeIfPresent(GrainAdjustments.self, forKey: .grain) ?? .neutral
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
