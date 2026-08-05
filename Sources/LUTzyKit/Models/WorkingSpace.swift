import CoreGraphics

/// The one colour space LUTzy works in.
///
/// Two things have to agree or the app is quietly wrong:
///
/// - **LUT interpolation** — the space `CIColorCubeWithColorSpace` interpolates the cube in.
/// - **Output encoding** — the space every raster and every export encoder writes.
///
/// Before this type they were four independent `CGColorSpace(name: .sRGB)!` literals that merely
/// happened to agree, plus **two sites that passed no colour space at all**: `createCGImage` in
/// `renderPreview` and `renderToNSImage` used the `CIContext` default while export forced sRGB. That
/// is byte-identical at sRGB today and wrong the moment a wide-gamut source or a P3 output appears —
/// a latent preview/export mismatch rather than a hypothetical one.
///
/// Every one of those sites now takes a `WorkingSpace`, defaulting to `.current`. Because they read
/// one value, they cannot desync: changing the default moves LUT interpolation and output encoding
/// together, atomically, in one line.
///
/// **Not covered, deliberately:** source *decode*. A P3 or Adobe RGB JPEG is still funnelled through
/// its embedded profile into the `CIContext` working space, exactly as before. This seam governs how
/// the cube is interpolated and how pixels are written out — not how they are read in.
///
/// **`RecipeExtractor` is deliberately pinned to `.sRGB`, not `.current`.** A derived `.cube` encodes
/// a transform *from* the baseline-render space *to* the JPEG's, and is later applied by
/// `CubeLUT.makeFilter` in `WorkingSpace.current`. For the derived LUT to be self-consistent, the
/// space it is fit in must equal the space it is applied in. Both are sRGB today. Enabling P3 means
/// re-fitting derive in P3 *or* stamping the build space onto the `CubeLUT` — never blindly threading
/// `.current` into the sampler, whose neutral RAW baseline is itself an sRGB-default render.
///
/// See `docs/PHASE2_SPEC.md` §4.4.
enum WorkingSpace: String, Codable, Sendable, Equatable, CaseIterable {
    case sRGB
    case displayP3

    var cgColorSpace: CGColorSpace {
        switch self {
        case .sRGB:
            // Both names are guaranteed-resolvable system constants, so the
            // force-unwrap is safe and — the point of this type — localized here.
            return CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3)!
        }
    }

    /// The space the app renders and exports in. Flipping this is the whole P3 switch — but read the
    /// derive caveat above first; it is a prerequisite, not a footnote.
    static let current: WorkingSpace = .sRGB
}
