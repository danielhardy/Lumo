import Foundation

/// A stable reference to a LUT, stored in an `EditDocument` in place of the LUT itself.
///
/// `CubeLUT` holds a non-`Codable` float table that runs to megabytes at 65³. Embedding one would
/// make `EditDocument` non-`Codable` and would copy the whole table into every undo snapshot, so the
/// document stores an ID and resolves it against the library.
///
/// **The wrapped value is a `String`, and deliberately so.** `CubeLUT.id` is a file path (or
/// `derived://…` for an in-memory LUT), which makes it deterministic: the same file scanned twice
/// yields the same ID. A `UUID`-backed ID would mint a fresh value on every `LUTLibrary.scan` — and
/// `saveDerivedLUT` triggers a rescan — so every persisted and undo document would silently stop
/// resolving the moment the library was rescanned. See `docs/PHASE2_SPEC.md` §4.3.
struct LUTID: Codable, Sendable, Hashable {
    let raw: String

    init(raw: String) {
        self.raw = raw
    }

    /// The ID of a specific LUT. Deterministic — derived from `CubeLUT.id`, nothing else.
    init(_ lut: CubeLUT) {
        self.raw = lut.id
    }

    /// True for a LUT that exists only in memory (a freshly derived one, before the user saves it).
    ///
    /// Its ID carries a `UUID`, so it *cannot* resolve after a relaunch. Persisting such a document
    /// is not wrong, but the LUT reference in it is expected to dangle; anything that writes
    /// documents to disk should decide deliberately what to do here rather than discover it later.
    var isDerived: Bool { raw.hasPrefix("derived://") }

    // Encoded as a bare string rather than `{"raw": "…"}`. This is a newtype over the path, and the
    // JSON should read like one.
    init(from decoder: Decoder) throws {
        self.raw = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

extension CubeLUT {
    /// This LUT's document-level identity.
    var lutID: LUTID { LUTID(self) }
}

extension Sequence where Element == CubeLUT {
    /// Resolve a document's `LUTID` against a scanned library.
    ///
    /// Deliberately a plain lookup over the scan results rather than a cached map: the library is
    /// re-scanned often enough that a cache would be the thing to go stale, and the ID is
    /// deterministic precisely so a fresh scan can answer this.
    func first(matching id: LUTID) -> CubeLUT? {
        first { $0.id == id.raw }
    }
}

/// The LUT half of an `EditDocument`: which LUT, and how much of it.
struct LUTSettings: Codable, Sendable, Equatable {
    /// `nil` means no LUT — the document passes colour through untouched.
    var lutID: LUTID?
    /// 0…1. Values outside that range are clamped where the LUT is applied
    /// (`CubeLUT.apply(to:intensity:)`), so a corrupt document cannot produce a nonsense render.
    var intensity: Double = 1.0 {
        didSet { intensity = Self.normalizedIntensity(intensity) }
    }

    /// No LUT. The starting state of every document.
    static let none = LUTSettings(lutID: nil, intensity: 1.0)

    /// True when this contributes nothing to the render — no LUT set, or a LUT at zero strength.
    var isIdentity: Bool { lutID == nil || !intensity.isFinite || intensity <= 0 }

    init(lutID: LUTID? = nil, intensity: Double = 1.0) {
        self.lutID = lutID
        // Keep malformed persisted values from escaping into the render graph. Non-finite strength
        // is safest as off; ordinary out-of-range values are normalized at the document boundary.
        self.intensity = Self.normalizedIntensity(intensity)
    }

    private static func normalizedIntensity(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, min(1, value))
    }

    private enum CodingKeys: String, CodingKey {
        case lutID, intensity
    }

    /// Decode each field independently. An older or hand-authored record that omits the optional
    /// `lutID` must mean "no LUT" rather than fail the whole edit.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            lutID: try container.decodeIfPresent(LUTID.self, forKey: .lutID),
            intensity: try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 1.0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Preserve the explicit null for None in the persisted shape while still accepting records
        // from older writers that omitted the optional key entirely.
        try container.encode(lutID, forKey: .lutID)
        try container.encode(intensity, forKey: .intensity)
    }
}
