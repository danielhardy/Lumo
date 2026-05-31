import Foundation
import CoreImage

/// Parses a .cube 3D LUT file and creates a CIFilter for GPU-accelerated color grading.
struct CubeLUT: Identifiable, Hashable {
    let id: String          // full file path (or a synthetic id for in-memory LUTs)
    let name: String        // display name (cleaned)
    let category: String    // folder name or "General"
    let url: URL
    let size: Int
    private let tableData: Data  // flattened RGBARGBA... float32 for Core Image

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
        sourceURL: URL? = nil
    ) {
        precondition(cube.count == size * size * size, "cube count must equal size^3")
        self.size = size
        self.name = name
        self.category = category
        self.url = sourceURL ?? URL(fileURLWithPath: "/dev/null")
        self.id = sourceURL?.path ?? "derived://\(name)/\(UUID().uuidString)"

        var floats = [Float]()
        floats.reserveCapacity(cube.count * 4)
        for v in cube {
            floats.append(v.x)
            floats.append(v.y)
            floats.append(v.z)
            floats.append(1.0)
        }
        self.tableData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: - Parsing

    init(url: URL, category: String = "General") throws {
        self.url = url
        self.id = url.path
        self.category = category

        let rawName = url.deletingPathExtension().lastPathComponent
        // Clean common suffixes
        var cleaned = rawName
        for suffix in ["_33_Rec709", "_65_Rec709", "_Rec709"] {
            cleaned = cleaned.replacingOccurrences(of: suffix, with: "")
        }
        self.name = cleaned

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var lutSize = 0
        var domainMin: SIMD3<Float> = .zero
        var domainMax: SIMD3<Float> = .one
        var rows: [(Float, Float, Float)] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                guard parts.count >= 2, let s = Int(parts[1]) else { continue }
                lutSize = s
            } else if trimmed.hasPrefix("DOMAIN_MIN") {
                let parts = trimmed.split(separator: " ").compactMap { Float($0) }
                if parts.count >= 3 { domainMin = SIMD3(parts[0], parts[1], parts[2]) }
            } else if trimmed.hasPrefix("DOMAIN_MAX") {
                let parts = trimmed.split(separator: " ").compactMap { Float($0) }
                if parts.count >= 3 { domainMax = SIMD3(parts[0], parts[1], parts[2]) }
            } else if !trimmed.hasPrefix("TITLE") {
                let parts = trimmed.split(separator: " ")
                if parts.count == 3,
                   let r = Float(parts[0]),
                   let g = Float(parts[1]),
                   let b = Float(parts[2]) {
                    rows.append((r, g, b))
                }
            }
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
        // Normalize from domain to [0,1] if needed.
        let scale = domainMax - domainMin
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

    // MARK: - Core Image Filter

    /// Creates a CIColorCube filter configured with this LUT.
    func makeFilter() -> CIFilter? {
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(tableData as NSData, forKey: "inputCubeData")
        filter.setValue(CGColorSpace(name: CGColorSpace.sRGB)!, forKey: "inputColorSpace")
        return filter
    }

    /// Apply this LUT to a CIImage and return the result.
    func apply(to image: CIImage) -> CIImage? {
        guard let filter = makeFilter() else { return nil }
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
    func apply(to image: CIImage, intensity: Double) -> CIImage? {
        let t = max(0, min(1, intensity))
        if t <= 0 { return image }
        guard let graded = apply(to: image) else { return nil }
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
        lines.append("# Generated by LUTzy")
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

enum LUTError: LocalizedError {
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return "Invalid .cube file: \(msg)"
        }
    }
}
