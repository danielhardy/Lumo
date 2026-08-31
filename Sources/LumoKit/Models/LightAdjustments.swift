import Foundation

/// A normalized point in the master RGB tone curve.
///
/// The curve editor can replace points without knowing about Core Image; this value is the
/// persistence contract consumed by the renderer. Inputs and outputs are normalized to 0...1 so the
/// same edit is independent of preview and export resolution.
struct LightCurvePoint: Codable, Equatable, Sendable {
    let input: Double
    let output: Double

    init(input: Double, output: Double) {
        self.input = Self.clamp(input, to: 0...1, default: 0)
        self.output = Self.clamp(output, to: 0...1, default: 0)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey { case input, output }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            input: try container.decodeIfPresent(Double.self, forKey: .input) ?? 0,
            output: try container.decodeIfPresent(Double.self, forKey: .output) ?? 0
        )
    }
}

/// The versioned, master RGB tone curve value used by `LightAdjustments`.
///
/// Points are sorted by input, duplicate inputs use the last point, and the endpoints are always
/// present. This makes malformed hand-edited documents deterministic and gives the eventual GPU
/// interpolator a well-defined domain. The diagonal is the exact neutral curve.
struct LightToneCurve: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let identity = LightToneCurve(points: [
        LightCurvePoint(input: 0, output: 0),
        LightCurvePoint(input: 1, output: 1),
    ])

    private(set) var version: Int
    var points: [LightCurvePoint] {
        didSet { points = Self.normalized(points) }
    }

    init(version: Int = Self.currentVersion, points: [LightCurvePoint] = Self.identity.points) {
        self.version = min(max(version, 1), Self.currentVersion)
        self.points = Self.normalized(points)
    }

    var isIdentity: Bool { self == Self.identity }

    /// True when the control points describe a non-decreasing transfer function.
    ///
    /// The value model preserves non-monotonic curves so a future editor can represent the full
    /// control-point space. This property lets callers validate or constrain that choice explicitly.
    var isMonotonic: Bool {
        zip(points, points.dropFirst()).allSatisfy { $0.output <= $1.output }
    }

    /// Interpolate the curve at a normalized input.
    ///
    /// Piecewise-linear interpolation is deliberate: unlike an unconstrained cubic spline it
    /// cannot overshoot between monotonic control points. Inputs outside the normalized domain are
    /// clamped, and a non-finite input is treated as zero so callers always receive a finite result.
    func value(at input: Double) -> Double {
        let x = input.isFinite ? min(max(input, 0), 1) : 0
        guard let upperIndex = points.firstIndex(where: { $0.input >= x }) else {
            return points.last?.output ?? 1
        }
        guard upperIndex > 0 else { return points[upperIndex].output }

        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let span = upper.input - lower.input
        guard span > 0 else { return upper.output }
        let fraction = (x - lower.input) / span
        return lower.output + (upper.output - lower.output) * fraction
    }

    private static func normalized(_ input: [LightCurvePoint]) -> [LightCurvePoint] {
        // Dictionary assignment gives duplicate inputs an explicit last-write-wins rule before
        // sorting; relying on sort stability would make a hand-edited document non-deterministic.
        var unique: [Double: LightCurvePoint] = [:]
        for point in input { unique[point.input] = point }
        let sorted = unique.values.sorted { $0.input < $1.input }
        var result: [LightCurvePoint] = []
        for point in sorted {
            if let last = result.last, last.input == point.input {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }

        if result.first?.input != 0 {
            result.insert(LightCurvePoint(input: 0, output: 0), at: 0)
        }
        if result.last?.input != 1 {
            result.append(LightCurvePoint(input: 1, output: 1))
        }
        return result.isEmpty ? Self.identity.points : result
    }

    private enum CodingKeys: String, CodingKey { case version, points }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Tone curve was saved by a newer version of Lumo (schema \(version))."
            )
        }
        self.init(
            version: version,
            points: try container.decodeIfPresent([LightCurvePoint].self, forKey: .points) ?? Self.identity.points
        )
    }
}

/// Photographer-facing global Light controls.
///
/// These values are intentionally independent of Core Image parameter units. Exposure is in EV;
/// the remaining sliders use the familiar -100...100 photographic scale. The renderer maps the
/// subset supported by the inherited adjustment nodes to those nodes; endpoint and curve controls
/// are rendered by dedicated GPU-backed stages.
struct LightAdjustments: Codable, Equatable, Sendable {
    static let neutral = LightAdjustments()

    static let exposureRange = -5.0...5.0
    static let contrastRange = -100.0...100.0
    static let highlightsRange = -100.0...100.0
    static let shadowsRange = -100.0...100.0
    static let whitesRange = -100.0...100.0
    static let blacksRange = -100.0...100.0

    var exposure: Double {
        didSet { exposure = Self.clamp(exposure, to: Self.exposureRange, default: 0) }
    }
    var contrast: Double {
        didSet { contrast = Self.clamp(contrast, to: Self.contrastRange, default: 0) }
    }
    var highlights: Double {
        didSet { highlights = Self.clamp(highlights, to: Self.highlightsRange, default: 0) }
    }
    var shadows: Double {
        didSet { shadows = Self.clamp(shadows, to: Self.shadowsRange, default: 0) }
    }
    var whites: Double {
        didSet { whites = Self.clamp(whites, to: Self.whitesRange, default: 0) }
    }
    var blacks: Double {
        didSet { blacks = Self.clamp(blacks, to: Self.blacksRange, default: 0) }
    }
    var toneCurve: LightToneCurve {
        didSet { toneCurve = LightToneCurve(version: toneCurve.version, points: toneCurve.points) }
    }

    init(
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        whites: Double = 0,
        blacks: Double = 0,
        toneCurve: LightToneCurve = .identity
    ) {
        self.exposure = Self.clamp(exposure, to: Self.exposureRange, default: 0)
        self.contrast = Self.clamp(contrast, to: Self.contrastRange, default: 0)
        self.highlights = Self.clamp(highlights, to: Self.highlightsRange, default: 0)
        self.shadows = Self.clamp(shadows, to: Self.shadowsRange, default: 0)
        self.whites = Self.clamp(whites, to: Self.whitesRange, default: 0)
        self.blacks = Self.clamp(blacks, to: Self.blacksRange, default: 0)
        self.toneCurve = LightToneCurve(version: toneCurve.version, points: toneCurve.points)
    }

    var isIdentity: Bool {
        exposure == 0 && contrast == 0 && highlights == 0 && shadows == 0 &&
            whites == 0 && blacks == 0 && toneCurve.isIdentity
    }

    /// Compatibility representation for callers that need the pre-refinement node values.
    ///
    /// `RenderPipeline` now uses a native EV node plus one tonal `CIToneCurve` for contrast,
    /// highlights, and shadows. This property remains available for migration/diagnostic code, but
    /// is deliberately not the render implementation: the individual inherited nodes are too broad
    /// for the photographer-facing Light behavior.
    var existingNodeRepresentation: [AdjustmentNode] {
        var nodes: [AdjustmentNode] = []
        if exposure != 0 { nodes.append(.exposure(ev: exposure)) }
        if contrast != 0 {
            nodes.append(.colorControls(brightness: 0, contrast: 1 + contrast / 100, saturation: 1))
        }
        if highlights != 0 || shadows != 0 {
            let highlightAmount = min(max(1 + highlights / 100, 0.3), 2)
            nodes.append(.highlightShadow(highlights: highlightAmount, shadows: shadows / 100))
        }
        return nodes
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case exposure, contrast, highlights, shadows, whites, blacks, toneCurve
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            exposure: try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
            contrast: try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
            highlights: try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
            shadows: try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
            whites: try container.decodeIfPresent(Double.self, forKey: .whites) ?? 0,
            blacks: try container.decodeIfPresent(Double.self, forKey: .blacks) ?? 0,
            toneCurve: try container.decodeIfPresent(LightToneCurve.self, forKey: .toneCurve) ?? .identity
        )
    }
}
