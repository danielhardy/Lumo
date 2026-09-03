import Foundation
import CoreImage
import CryptoKit

/// Where a Look came from. Bundled Looks are packaged with Lumo and are immutable; all other
/// sources are user-owned or session-owned values and retain the existing import/save semantics.
enum LUTSource: String, Sendable, Equatable {
    case bundled
    case user
    case derived

    var displayName: String {
        switch self {
        case .bundled: return "Starter"
        case .user: return "User"
        case .derived: return "Session"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .bundled: return "Starter Look, read-only"
        case .user: return "User Look"
        case .derived: return "Session Look"
        }
    }
}

/// Parses a .cube 3D LUT file and creates a CIFilter for GPU-accelerated color grading.
struct CubeLUT: Identifiable, Hashable, Sendable {
    /// Core Image handles the common 3D cube resolutions through 65³ reliably. Larger files are
    /// valid according to the interchange specification, but expanding them into a
    /// `CIColorCubeWithColorSpace` table is not a practical macOS editor operation (and would let
    /// an accidentally huge file allocate unbounded memory). The supported boundary is deliberately
    /// explicit so an unsupported file fails before any large allocation.
    static let minimumSupportedSize = 2
    static let maximumSupportedSize = 65
    static let supportedFileExtensions = Set(["cube", "look"])

    let id: String          // full file path (or a synthetic id for in-memory LUTs)
    let name: String        // display name (cleaned)
    let category: String    // folder name or "General"
    let url: URL
    let size: Int
    let source: LUTSource
    private let tableData: Data  // flattened RGBARGBA... float32 for Core Image

    /// Includes table contents as well as the stable LUT ID, so replacing a file in place cannot
    /// reuse a final preview merely because the path stayed the same.
    var cacheFingerprint: String {
        RenderCacheHash.digest(tableData) + ":" + id
    }

    // MARK: - Hashable

    static func == (lhs: CubeLUT, rhs: CubeLUT) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - In-memory init (used by RecipeExtractor before the user saves)

    /// Build a CubeLUT directly from cube values, without touching disk.
    /// `cube` must be `size * size * size` SIMD3<Float> entries with R varying
    /// fastest, then G, then B (same ordering as the .cube file format).
    init(
        cube: [SIMD3<Float>],
        size: Int,
        name: String,
        category: String = "Derived",
        sourceURL: URL? = nil,
        source: LUTSource = .derived
    ) {
        precondition(cube.count == size * size * size, "cube count must equal size^3")
        self.size = size
        self.name = name
        self.category = category
        self.url = sourceURL ?? URL(fileURLWithPath: "/dev/null")
        self.source = source

        var floats = [Float]()
        floats.reserveCapacity(cube.count * 4)
        for v in cube {
            floats.append(v.x)
            floats.append(v.y)
            floats.append(v.z)
            floats.append(1.0)
        }
        let table = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        self.tableData = table
        // The table has to be built before the ID, because the ID is made from it.
        self.id = sourceURL.map(Self.canonicalPath) ?? Self.derivedID(name: name, table: table)
    }

    /// The identity of a LUT that exists only in memory: `derived://<name>/<hash of the table>`.
    ///
    /// **Content-derived, not random.** `docs/PHASE2_SPEC.md` §4.3 rules out a `UUID` because it
    /// mints fresh identity on construction, and that argument does not stop at the library scan it
    /// is written about — a `UUID()` here did the same thing one level down. Hashing the table means
    /// the same cube is always the same LUT, which is also the honest answer: two cubes with the same
    /// contents render identically and are interchangeable in `LUTFilterCache`.
    ///
    /// **`CryptoKit`, not `Hasher`.** Swift's `Hasher` is seeded per process, so an ID built from it
    /// would be stable within a launch and silently different across launches — the failure mode
    /// §4.3 exists to prevent, and one no single-process test can see.
    /// `LUTIDTests.testTheDerivedIDIsStableAcrossProcesses` pins a literal for that reason.
    ///
    /// The name is included because it identifies the source pair a derive came from, and two
    /// unrelated derives should not share a registry slot on the strength of a coincidence.
    ///
    /// 64 bits of the digest. This distinguishes the handful of derives in one session, not the
    /// world's LUTs.
    private static func derivedID(name: String, table: Data) -> String {
        let digest = SHA256.hash(data: table)
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "derived://\(name)/\(hex)"
    }

    // MARK: - Parsing

    init(
        url: URL,
        category: String = "General",
        source: LUTSource = .user,
        displayName: String? = nil
    ) throws {
        self.url = url
        self.id = Self.canonicalPath(url)
        self.category = category
        self.source = source

        let rawName = url.deletingPathExtension().lastPathComponent
        // Clean common suffixes
        var cleaned = rawName
        for suffix in ["_33_Rec709", "_65_Rec709", "_Rec709"] {
            cleaned = cleaned.replacingOccurrences(of: suffix, with: "")
        }
        self.name = cleaned

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw LUTError.unreadable(error.localizedDescription)
        }
        let lines = content.components(separatedBy: .newlines)

        var lutSize = 0
        var domainMin: SIMD3<Float> = .zero
        var domainMax: SIMD3<Float> = .one
        var rows: [(Float, Float, Float)] = []
        var sawSize = false
        var sawOneDimensionalSize = false
        var sawTableData = false

        for (lineNumber, rawLine) in lines.enumerated() {
            // A UTF-8 BOM is legal in files emitted by some Windows tools. It is metadata, not part
            // of the first keyword. The parser otherwise treats the file as ordinary UTF-8 text.
            let line = lineNumber == 0
                ? rawLine.replacingOccurrences(of: "\u{FEFF}", with: "")
                : rawLine
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Vendors commonly put a trailing comment after a data row. The `TITLE` value is not
            // used as the identity, so treating a # in metadata as a comment is harmless here.
            let withoutComment = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
            if withoutComment.isEmpty { continue }
            let parts = withoutComment.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let first = parts.first else { continue }

            if first == "LUT_3D_SIZE" {
                guard !sawTableData else {
                    throw LUTError.invalidFormat("LUT_3D_SIZE must appear before table data (line \(lineNumber + 1))")
                }
                guard !sawSize else {
                    throw LUTError.invalidFormat("LUT_3D_SIZE appears more than once")
                }
                guard parts.count == 2, let s = Int(parts[1]) else {
                    throw LUTError.invalidFormat("invalid LUT_3D_SIZE on line \(lineNumber + 1)")
                }
                guard s >= Self.minimumSupportedSize, s <= Self.maximumSupportedSize else {
                    throw LUTError.invalidFormat(
                        "3D size \(s) is unsupported; use a size from \(Self.minimumSupportedSize) through \(Self.maximumSupportedSize)"
                    )
                }
                lutSize = s
                sawSize = true
                continue
            }

            if first == "LUT_1D_SIZE" {
                sawOneDimensionalSize = true
                continue
            }

            if first == "DOMAIN_MIN" || first == "DOMAIN_MAX" {
                guard !sawTableData else {
                    throw LUTError.invalidFormat("\(first) must appear before table data (line \(lineNumber + 1))")
                }
                guard parts.count == 4,
                      let r = Float(parts[1]), let g = Float(parts[2]), let b = Float(parts[3]),
                      r.isFinite, g.isFinite, b.isFinite
                else {
                    throw LUTError.invalidFormat("\(first) requires three finite numbers (line \(lineNumber + 1))")
                }
                let value = SIMD3(r, g, b)
                if first == "DOMAIN_MIN" {
                    domainMin = value
                } else {
                    domainMax = value
                }
                continue
            }

            // `LUT_3D_INPUT_RANGE` is a widely emitted compatibility spelling for a uniform
            // DOMAIN_MIN/DOMAIN_MAX pair. It is not needed for files using the standard keywords,
            // but accepting it makes vendor exports interoperable without changing the render path.
            if first == "LUT_3D_INPUT_RANGE" {
                guard !sawTableData, parts.count == 3,
                      let minimum = Float(parts[1]), let maximum = Float(parts[2]),
                      minimum.isFinite, maximum.isFinite
                else {
                    throw LUTError.invalidFormat("LUT_3D_INPUT_RANGE requires two finite numbers (line \(lineNumber + 1))")
                }
                domainMin = SIMD3(repeating: minimum)
                domainMax = SIMD3(repeating: maximum)
                continue
            }

            if first == "TITLE" {
                // TITLE is display metadata. Lumo keeps the filename as the stable, predictable
                // browser name because it must not change when a vendor rewrites metadata in place.
                continue
            }

            let numericValues = parts.compactMap { Float($0) }
            if numericValues.count == parts.count {
                if sawOneDimensionalSize && !sawSize {
                    throw LUTError.unsupported("1D .cube LUTs are not supported; import a 3D LUT")
                }
                guard sawSize else {
                    throw LUTError.invalidFormat("table data appears before LUT_3D_SIZE (line \(lineNumber + 1))")
                }
                guard parts.count == 3,
                      numericValues.allSatisfy(\.isFinite)
                else {
                    throw LUTError.invalidFormat("table row must contain three finite numbers (line \(lineNumber + 1))")
                }
                rows.append((numericValues[0], numericValues[1], numericValues[2]))
                sawTableData = true
            } else if numericValues.isEmpty {
                // Unknown vendor metadata is safe to ignore. Numeric-looking malformed rows are
                // rejected above so a broken LUT cannot be silently shortened or partially applied.
                continue
            } else {
                throw LUTError.invalidFormat("unrecognized numeric line (line \(lineNumber + 1))")
            }
        }

        if sawOneDimensionalSize {
            throw LUTError.unsupported("1D .cube LUTs are not supported; import a 3D LUT")
        }
        guard lutSize > 0 else {
            throw LUTError.invalidFormat("LUT_3D_SIZE not found")
        }
        let expected = lutSize * lutSize * lutSize
        guard rows.count == expected else {
            throw LUTError.invalidFormat("Expected \(expected) entries, got \(rows.count)")
        }

        self.size = lutSize

        // Build Core Image color cube data: RGBA float32, R varies fastest.
        // .cube format: R fastest, G middle, B slowest — same as Core Image expects.
        // Normalize from domain to [0,1] if needed. A degenerate domain (min ==
        // max on any axis) would divide by zero and fill the table with NaN, so
        // treat that axis as the default 0…1 range instead.
        for axis in 0..<3 where domainMax[axis] < domainMin[axis] {
            throw LUTError.invalidFormat("DOMAIN_MAX must not be below DOMAIN_MIN")
        }

        var scale = domainMax - domainMin
        for axis in 0..<3 where !(scale[axis] > 0) {
            domainMin[axis] = 0
            scale[axis] = 1
        }
        var floats = [Float]()
        floats.reserveCapacity(expected * 4)

        for row in rows {
            let r = (row.0 - domainMin.x) / scale.x
            let g = (row.1 - domainMin.y) / scale.y
            let b = (row.2 - domainMin.z) / scale.z
            floats.append(r)
            floats.append(g)
            floats.append(b)
            floats.append(1.0) // alpha
        }

        self.tableData = floats.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    // MARK: - Inspection

    /// The flattened RGBA float table handed to Core Image, as floats.
    ///
    /// Exists for tests: rendering through Core Image clamps NaN to 0, so a
    /// corrupt table is invisible from the output side and has to be inspected
    /// directly.
    var tableFloats: [Float] {
        tableData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    // MARK: - Core Image Filter

    /// Creates a CIColorCube filter configured with this LUT.
    ///
    /// `space` is the **LUT interpolation space** — one half of the colour seam. It must stay in
    /// lockstep with the output encoding space; both default to `WorkingSpace.current` so they cannot
    /// drift apart. See `WorkingSpace`.
    func makeFilter(space: WorkingSpace = .current) -> CIFilter? {
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(tableData as NSData, forKey: "inputCubeData")
        filter.setValue(space.cgColorSpace, forKey: "inputColorSpace")
        return filter
    }

    /// Apply this LUT to a CIImage and return the result.
    func apply(to image: CIImage, space: WorkingSpace = .current) -> CIImage? {
        guard let filter = makeFilter(space: space) else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage
    }

    /// Apply this LUT at a given strength and return the result.
    ///
    /// `intensity` is clamped to 0...1: `1` is the full LUT, `0` is the
    /// untouched original, and values in between crossfade the graded result
    /// back toward the original via `CIDissolveTransition`. The graded image
    /// and the source share the same extent (a color cube is a per-pixel
    /// remap), so the dissolve is a clean opacity blend.
    ///
    /// Note the crossfade happens in the `CIContext`'s working space (≈ linear light), **not** in
    /// `space` — that argument governs cube interpolation only. Measured: a to-black LUT over white
    /// reads 188 at intensity 0.5, where a perceptual mix would read ~128. See `docs/PHASE2_SPEC.md`
    /// §8.1; changing it later is a visible look change for every sub-100% render.
    func apply(to image: CIImage, intensity: Double, space: WorkingSpace = .current) -> CIImage? {
        let t = max(0, min(1, intensity))
        // Build nothing when the LUT contributes nothing — a 65³ cube is ~4.4 MB to hand over.
        if t <= 0 { return image }
        return apply(to: image, intensity: t, using: makeFilter(space: space))
    }

    /// The shared body of the two `apply` overloads, taking a cube filter rather than making one.
    ///
    /// Exists so `RenderPipeline` can pass a filter from `LUTFilterCache` without a second copy of the
    /// dissolve logic. Two implementations of a crossfade would be two things to keep in step, and
    /// §8.1 of the spec is explicit that the blend's behaviour is shipping behaviour — a divergence
    /// here would be a visible look change on one path only.
    func apply(to image: CIImage, intensity: Double, using cubeFilter: CIFilter?) -> CIImage? {
        let t = max(0, min(1, intensity))
        if t <= 0 { return image }
        guard let cubeFilter else { return nil }

        cubeFilter.setValue(image, forKey: kCIInputImageKey)
        guard let graded = cubeFilter.outputImage else { return nil }
        if t >= 1 { return graded }

        guard let mix = CIFilter(name: "CIDissolveTransition") else { return graded }
        mix.setValue(image, forKey: kCIInputImageKey)
        mix.setValue(graded, forKey: kCIInputTargetImageKey)
        mix.setValue(t, forKey: kCIInputTimeKey)
        return mix.outputImage ?? graded
    }

    // MARK: - Writing

    /// Serialize a cube to .cube text format. Inverse of the parser above.
    /// Index ordering: R fastest, G middle, B slowest.
    static func cubeFileContents(
        cube: [SIMD3<Float>],
        size: Int,
        title: String
    ) -> String {
        precondition(cube.count == size * size * size, "cube count must equal size^3")
        var lines: [String] = []
        lines.reserveCapacity(cube.count + 6)
        lines.append("# Generated by Lumo")
        lines.append("TITLE \"\(title)\"")
        lines.append("LUT_3D_SIZE \(size)")
        lines.append("DOMAIN_MIN 0.0 0.0 0.0")
        lines.append("DOMAIN_MAX 1.0 1.0 1.0")
        for v in cube {
            let r = max(0, min(1, v.x))
            let g = max(0, min(1, v.y))
            let b = max(0, min(1, v.z))
            lines.append(String(format: "%.6f %.6f %.6f", r, g, b))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Write a cube to disk in .cube format.
    static func write(
        cube: [SIMD3<Float>],
        size: Int,
        title: String,
        to url: URL
    ) throws {
        let text = cubeFileContents(cube: cube, size: size, title: title)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Errors

enum LUTError: LocalizedError, Sendable {
    case invalidFormat(String)
    case unsupported(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return "Invalid .cube file: \(msg)"
        case .unsupported(let msg): return "Unsupported LUT file: \(msg)"
        case .unreadable(let msg): return "Could not read LUT file: \(msg)"
        }
    }
}
