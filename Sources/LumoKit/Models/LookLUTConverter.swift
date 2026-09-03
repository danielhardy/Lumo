import Foundation
import CoreImage

/// The support contract for converting an `EditDocument` into a portable 3D LUT.
///
/// This is deliberately data rather than a view concern. A `.cube` is a global RGB transform, so
/// the support list must be explicit and versioned instead of silently flattening source or spatial
/// edits into a file that cannot reproduce them.
struct LUTSupportMatrix: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum Disposition: String, Codable, Sendable {
        case included
        case omitted
    }

    struct Entry: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let disposition: Disposition
        let explanation: String
    }

    let version: Int
    let entries: [Entry]

    var included: [Entry] { entries.filter { $0.disposition == .included } }
    var omitted: [Entry] { entries.filter { $0.disposition == .omitted } }
    var hasOmissions: Bool { !omitted.isEmpty }

    var omittedNames: [String] { omitted.map(\.name) }

    /// Text suitable for a confirmation sheet and for the comments in the exported `.cube`.
    var omissionMessage: String? {
        guard hasOmissions else { return nil }
        return omittedNames.joined(separator: ", ") + " will be omitted because a LUT cannot preserve source or spatial edits."
    }

    static func make(for document: EditDocument) -> LUTSupportMatrix {
        var entries: [Entry] = []

        if !document.rawDevelop.isNeutral {
            entries.append(Entry(
                id: "raw-develop", name: "RAW develop", disposition: .omitted,
                explanation: "RAW decoding and camera/source settings are not part of a global RGB LUT."
            ))
        }
        if !document.light.isIdentity {
            entries.append(Entry(
                id: "light", name: "Light and tone", disposition: .included,
                explanation: "Verified global tone stages are sampled into the LUT."
            ))
        }
        if !document.color.isIdentity {
            entries.append(Entry(
                id: "color", name: "Color", disposition: .included,
                explanation: "Verified global color, mixer, and grading stages are sampled into the LUT."
            ))
        }
        if document.effects.texture != 0 || document.effects.clarity != 0 || document.effects.dehaze != 0 {
            entries.append(Entry(
                id: "spatial-effects", name: "Texture, Clarity, or Dehaze", disposition: .omitted,
                explanation: "These effects use spatial neighborhoods and cannot be represented by a per-pixel cube."
            ))
        }
        if !document.effects.vignette.isIdentity {
            entries.append(Entry(
                id: "vignette", name: "Vignette", disposition: .omitted,
                explanation: "Vignette depends on image geometry and is excluded from a global LUT."
            ))
        }
        if !document.effects.grain.isIdentity {
            entries.append(Entry(
                id: "grain", name: "Grain", disposition: .omitted,
                explanation: "Grain is spatial and source/size dependent, so it is excluded from a LUT."
            ))
        }
        if !document.crop.isIdentity {
            entries.append(Entry(
                id: "crop", name: "Crop and rotation", disposition: .omitted,
                explanation: "Framing and rotation change composition rather than RGB values."
            ))
        }

        for (index, node) in document.adjustments.enumerated() where !node.isIdentity {
            entries.append(Entry(
                id: "adjustment-\(index)", name: "Adjustment \(index + 1): \(node.displayName)", disposition: .included,
                explanation: "Verified per-pixel adjustment stage; order is preserved."
            ))
        }

        if !document.lut.isIdentity {
            entries.append(Entry(
                id: "look", name: "Existing Look", disposition: .included,
                explanation: "The resolved existing 3D Look is composed into the sampled global transform."
            ))
        }

        return LUTSupportMatrix(version: currentVersion, entries: entries)
    }
}

extension AdjustmentNode {
    fileprivate var displayName: String {
        switch self {
        case .exposure: return "Exposure"
        case .colorControls: return "Color controls"
        case .highlightShadow: return "Highlights and shadows"
        case .temperatureTint: return "Temperature and tint"
        case .vibrance: return "Vibrance"
        }
    }
}

struct LUTConversionVerification: Equatable, Sendable {
    static let defaultTolerance = 0.03

    let passed: Bool
    let maxAbsoluteChannelError: Double
    let tolerance: Double
    let sampleCount: Int
}

struct LookLUTConversion: Sendable {
    let cube: [SIMD3<Float>]
    let size: Int
    let workingSpace: WorkingSpace
    let domainMin: SIMD3<Float>
    let domainMax: SIMD3<Float>
    let supportMatrix: LUTSupportMatrix
    let verification: LUTConversionVerification

    /// The document actually sampled. It is exposed for tests and diagnostics so an omitted edit
    /// can never be mistaken for one that was flattened into the cube.
    let sampledDocument: EditDocument

    func cubeText(title: String) -> String {
        let included = supportMatrix.included.map(\.name).joined(separator: ", ")
        let omitted = supportMatrix.omitted.map(\.name).joined(separator: ", ")
        var comments = [
            "Lumo Look export",
            "Support matrix version: \(supportMatrix.version)",
            "LUT size: \(size)^3",
            "Working color space: \(workingSpace.rawValue)",
            "DOMAIN_MIN: 0.0 0.0 0.0",
            "DOMAIN_MAX: 1.0 1.0 1.0",
            "Conversion tolerance (maximum absolute channel error): \(String(format: "%.3f", verification.tolerance))",
            "Verification maximum absolute channel error: \(String(format: "%.6f", verification.maxAbsoluteChannelError))",
            "Included stages: \(included.isEmpty ? "none" : included)",
            "Omitted stages: \(omitted.isEmpty ? "none" : omitted)",
            "Limits: this LUT preserves global RGB color/tone changes only; it does not reproduce RAW development, crop/rotation, masking, vignette, grain, or other spatial/source-dependent edits."
        ]
        if let message = supportMatrix.omissionMessage {
            comments.append("Notice: \(message)")
        }
        return CubeLUT.cubeFileContents(cube: cube, size: size, title: title, comments: comments)
    }
}

enum LookLUTConversionError: LocalizedError, Sendable {
    case invalidSize
    case unresolvedLook
    case verificationFailed(maxError: Double, tolerance: Double)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .invalidSize: return "The LUT size must be between 2 and 65 samples per axis."
        case .unresolvedLook: return "The active Look is unavailable, so it cannot be included in the saved Look."
        case .verificationFailed(let maxError, let tolerance):
            return String(format: "The Look could not be verified within the %.3f conversion tolerance (measured %.3f).", tolerance, maxError)
        case .renderFailed: return "The active edits could not be sampled into a LUT."
        }
    }
}

/// Converts the global, verified portion of a document by evaluating the same Core Image graph used
/// for preview/export at the lattice points of a standard `.cube`.
enum LookLUTConverter {
    static let defaultSize = 33
    static let verificationResolution = 5
    /// Keep sampled LUT/probe images below the maximum 1D texture width supported by Metal.
    private static let samplesPerRow = 8192

    static func convert(
        document: EditDocument,
        lut: CubeLUT?,
        size: Int = defaultSize,
        space: WorkingSpace = .current,
        tolerance: Double = LUTConversionVerification.defaultTolerance
    ) throws -> LookLUTConversion {
        guard size >= CubeLUT.minimumSupportedSize, size <= CubeLUT.maximumSupportedSize else {
            throw LookLUTConversionError.invalidSize
        }
        let matrix = LUTSupportMatrix.make(for: document)
        guard document.lut.isIdentity || lut != nil else {
            throw LookLUTConversionError.unresolvedLook
        }

        // RAW decoding, framing, and every spatial effect are intentionally neutralized. The
        // remaining graph is made only of verified per-pixel stages and keeps their original order.
        let sampledDocument = EditDocument(
            version: document.version,
            rawDevelop: .neutral,
            light: document.light,
            color: document.color,
            effects: .neutral,
            crop: .neutral,
            adjustments: document.adjustments,
            lut: document.lut
        )

        let context = CIContext(options: [CIContextOption.cacheIntermediates: false])
        let input = makeGridInput(size: size, space: space)
        let output = RenderPipeline.buildImage(
            developed: input,
            document: sampledDocument,
            lut: lut,
            space: space,
            grainSeed: 0
        )
        let cube = try renderRGB(output, count: size * size * size, context: context, space: space)

        let generated = CubeLUT(cube: cube, size: size, name: "verification")
        let verification = try verify(
            document: sampledDocument,
            originalLUT: lut,
            generated: generated,
            context: context,
            space: space,
            tolerance: tolerance
        )
        guard verification.passed else {
            throw LookLUTConversionError.verificationFailed(
                maxError: verification.maxAbsoluteChannelError, tolerance: tolerance
            )
        }

        return LookLUTConversion(
            cube: cube, size: size, workingSpace: space,
            domainMin: .zero, domainMax: .one,
            supportMatrix: matrix, verification: verification,
            sampledDocument: sampledDocument
        )
    }

    private static func makeGridInput(size: Int, space: WorkingSpace) -> CIImage {
        let count = size * size * size
        let width = min(samplesPerRow, count)
        let height = (count + width - 1) / width
        var values = [Float](repeating: 1, count: width * height * 4)
        let denominator = Float(size - 1)
        var index = 0
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    // Keep the source coordinates on the exact normalized cube lattice. Using
                    // RGBA8 here shifts most nodes from r/(size - 1) to a nearby 8-bit value
                    // (for example, 1/32 becomes 8/255), which makes the generated cube subtly
                    // misregistered and can push an otherwise valid conversion over the verifier's
                    // tolerance.
                    values[index * 4] = Float(r) / denominator
                    values[index * 4 + 1] = Float(g) / denominator
                    values[index * 4 + 2] = Float(b) / denominator
                    index += 1
                }
            }
        }
        return CIImage(
            bitmapData: Data(bytes: values, count: values.count * MemoryLayout<Float>.size),
            bytesPerRow: width * MemoryLayout<Float>.size * 4,
            size: CGSize(width: width, height: height), format: .RGBAf,
            colorSpace: space.cgColorSpace
        )
    }

    private static func makeProbeInput(space: WorkingSpace) -> CIImage {
        let resolution = verificationResolution
        let count = resolution * resolution * resolution
        let width = min(samplesPerRow, count)
        let height = (count + width - 1) / width
        var values = [Float](repeating: 1, count: width * height * 4)
        var index = 0
        for b in 0..<resolution {
            for g in 0..<resolution {
                for r in 0..<resolution {
                    // Offset the probes from the cube lattice so interpolation, rather than just
                    // table-node equality, is verified.
                    let denominator = Float(resolution)
                    values[index * 4] = Float(r) / denominator
                    values[index * 4 + 1] = Float(g) / denominator
                    values[index * 4 + 2] = Float(b) / denominator
                    index += 1
                }
            }
        }
        return CIImage(
            bitmapData: Data(bytes: values, count: values.count * MemoryLayout<Float>.size),
            bytesPerRow: width * MemoryLayout<Float>.size * 4,
            size: CGSize(width: width, height: height), format: .RGBAf,
            colorSpace: space.cgColorSpace
        )
    }

    private static func verify(
        document: EditDocument,
        originalLUT: CubeLUT?,
        generated: CubeLUT,
        context: CIContext,
        space: WorkingSpace,
        tolerance: Double
    ) throws -> LUTConversionVerification {
        let input = makeProbeInput(space: space)
        let reference = RenderPipeline.buildImage(
            developed: input, document: document, lut: originalLUT, space: space, grainSeed: 0
        )
        let generatedDocument = EditDocument(lut: LUTSettings(lutID: generated.lutID))
        let approximation = RenderPipeline.buildImage(
            developed: input, document: generatedDocument, lut: generated, space: space, grainSeed: 0
        )
        let count = verificationResolution * verificationResolution * verificationResolution
        let expected = try renderRGB(reference, count: count, context: context, space: space)
        let actual = try renderRGB(approximation, count: count, context: context, space: space)
        let maxError = zip(expected, actual).map { pair in
            max(abs(Double(pair.0.x - pair.1.x)), max(abs(Double(pair.0.y - pair.1.y)), abs(Double(pair.0.z - pair.1.z))))
        }.max() ?? 0
        return LUTConversionVerification(
            passed: maxError <= tolerance,
            maxAbsoluteChannelError: maxError,
            tolerance: tolerance,
            sampleCount: count
        )
    }

    private static func renderRGB(
        _ image: CIImage, count: Int, context: CIContext, space: WorkingSpace
    ) throws -> [SIMD3<Float>] {
        let width = Int(image.extent.width.rounded())
        let height = Int(image.extent.height.rounded())
        guard width > 0, height > 0, width * height >= count else {
            throw LookLUTConversionError.renderFailed
        }
        var values = [Float](repeating: 0, count: width * height * 4)
        let bounds = CGRect(
            x: image.extent.minX, y: image.extent.minY,
            width: CGFloat(width), height: CGFloat(height)
        )
        values.withUnsafeMutableBytes { raw in
            context.render(
                image, toBitmap: raw.baseAddress!, rowBytes: width * MemoryLayout<Float>.size * 4,
                bounds: bounds, format: .RGBAf, colorSpace: space.cgColorSpace
            )
        }
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let x = index % width
            let y = index / width
            let offset = (y * width + x) * 4
            let value = SIMD3(values[offset], values[offset + 1], values[offset + 2])
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
                throw LookLUTConversionError.renderFailed
            }
            result.append(SIMD3(max(0, min(1, value.x)), max(0, min(1, value.y)), max(0, min(1, value.z))))
        }
        return result
    }
}

enum LookNameValidator {
    static func validate(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", name.count <= 120 else { return nil }
        guard !name.contains("/"), !name.contains("\\"), !name.contains(":") else { return nil }
        guard !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return name
    }
}
