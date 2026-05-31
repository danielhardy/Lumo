import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ImageIO
import simd

/// Derives a 3D LUT from a (RAW, JPG) pair by sampling pixel correspondences
/// after rendering the RAW through the same default `CIRAWFilter` pipeline that
/// the rest of LUTzy uses to render RAWs. The derived LUT therefore drops back
/// into the existing `CIColorCubeWithColorSpace` apply path with no baseline
/// mismatch.
///
/// Pipeline:
///   1. Render RAW with default CIRAWFilter → CIImage (the "neutral baseline"
///      that LUTzy itself would feed to a cube filter)
///   2. Decode JPG → CIImage
///   3. Lanczos-scale the RAW render down to JPG dimensions
///   4. Box-blur the JPG to compute an edge mask (sharpening contaminates
///      chroma at high frequencies)
///   5. Render all three to RGBA8 byte buffers in sRGB
///   6. Find integer-pixel alignment via brute-force luma cross-correlation on
///      a center patch
///   7. Sample N random pixels; keep ones in smooth (low-edge) regions
///   8. Accumulate samples into an N³ cube (sum + count per cell)
///   9. Smooth empty cells by iterative pull from filled neighbors; anchor
///      remaining cells to identity
///  10. Build the report: tone curve, saturation ratio, sharpening estimate,
///      coverage %, alignment shift, EXIF camera info
struct RecipeExtractor {

    struct Options {
        var cubeSize: Int = 33
        var blurRadius: Float = 3
        /// Edge-mask threshold in 0…1 luma-difference space.
        /// 2/255 ≈ 0.0078 — anything sharper than that is an edge.
        var edgeThreshold: Float = 2.0 / 255.0
        /// Number of random pixel coordinates to draw before edge-masking.
        /// A 5-10x oversample factor leaves ~200k usable samples.
        var randomDrawCount: Int = 2_000_000
        /// Maximum smooth-region samples to actually accumulate.
        var samplesTarget: Int = 200_000
        /// Iterations of neighbor-pull smoothing for empty cube cells.
        var smoothingIterations: Int = 8
        /// Half-window for the alignment search (±N pixels).
        var alignmentSearchRadius: Int = 4
    }

    enum ExtractorError: LocalizedError {
        case cannotLoadRAW(String)
        case cannotLoadJPG(String)
        case renderFailed(String)
        case zeroSamples

        var errorDescription: String? {
            switch self {
            case .cannotLoadRAW(let n): return "Cannot load RAW: \(n)"
            case .cannotLoadJPG(let n): return "Cannot load JPG: \(n)"
            case .renderFailed(let s):  return "Render failed: \(s)"
            case .zeroSamples:          return "No usable samples found in the smooth regions of the image"
            }
        }
    }

    struct Result {
        let cube: [SIMD3<Float>]   // size³ entries, R fastest
        let size: Int
        let report: RecipeReport
    }

    /// Run the full extraction pipeline. Safe to call from a background task.
    /// `progress` is invoked with values in [0,1] and a short stage label.
    static func derive(
        rawURL: URL,
        jpgURL: URL,
        options: Options = Options(),
        progress: ((Double, String) -> Void)? = nil
    ) throws -> Result {

        let context = makeContext()
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

        progress?(0.05, "Loading RAW…")

        // 1. RAW → CIImage at neutral CIRAWFilter defaults. Routed through the
        //    single shared helper on ImageProcessor so the derive baseline
        //    can't drift from the render path — and stays independent of any
        //    user develop settings.
        guard let rawImage = ImageProcessor.developRAWNeutral(at: rawURL) else {
            throw ExtractorError.cannotLoadRAW(rawURL.lastPathComponent)
        }

        progress?(0.15, "Loading JPG…")

        // 2. JPG → CIImage. CIImage interprets the embedded color space.
        guard let jpgImage = CIImage(contentsOf: jpgURL) else {
            throw ExtractorError.cannotLoadJPG(jpgURL.lastPathComponent)
        }

        // Both images get aligned to the JPG's extent, in JPG pixel space.
        // CIImage extents from RAW filters can have a non-zero origin — we
        // normalize everything into a (0,0)-origin output rectangle.
        let jpgOrigin = jpgImage.extent
        let outputSize = CGSize(width: jpgOrigin.width, height: jpgOrigin.height)
        let outputRect = CGRect(origin: .zero, size: outputSize)

        progress?(0.25, "Scaling RAW to JPG resolution…")

        // 3. Lanczos-scale the RAW render to JPG dimensions
        let rawScaled = lanczosScale(rawImage, to: outputSize)
        let rawTranslated = rawScaled.transformed(
            by: CGAffineTransform(translationX: -rawScaled.extent.origin.x,
                                  y: -rawScaled.extent.origin.y)
        )

        // Move the JPG to a (0,0) origin too
        let jpgTranslated = jpgImage.transformed(
            by: CGAffineTransform(translationX: -jpgOrigin.origin.x,
                                  y: -jpgOrigin.origin.y)
        )

        progress?(0.35, "Computing edge mask…")

        // 4. Box-blur the JPG; |jpg − blurred| becomes the edge proxy
        let jpgBlurred = boxBlur(jpgTranslated, radius: options.blurRadius)
            .cropped(to: outputRect)

        // 5. Render all three to RGBA8 byte buffers
        guard let rawBuf = render(rawTranslated, to: outputRect, context: context, colorSpace: sRGB) else {
            throw ExtractorError.renderFailed("neutral RAW")
        }
        guard let jpgBuf = render(jpgTranslated, to: outputRect, context: context, colorSpace: sRGB) else {
            throw ExtractorError.renderFailed("JPG")
        }
        guard let blurBuf = render(jpgBlurred, to: outputRect, context: context, colorSpace: sRGB) else {
            throw ExtractorError.renderFailed("blurred JPG")
        }

        progress?(0.50, "Aligning…")

        // 6. Integer-pixel alignment via brute-force cross-correlation
        let alignment = computeAlignment(
            rawBuf: rawBuf,
            jpgBuf: jpgBuf,
            radius: options.alignmentSearchRadius
        )

        progress?(0.60, "Sampling…")

        // 7. Random-sample then keep smooth regions.
        // The actual loop lives in `runSampleLoop` so the type-checker doesn't
        // have to chew through 100+ lines of arithmetic in one expression.
        let stats = runSampleLoop(
            rawBuf: rawBuf,
            jpgBuf: jpgBuf,
            blurBuf: blurBuf,
            alignment: alignment,
            options: options
        )

        guard stats.sampleCount > 0 else {
            throw ExtractorError.zeroSamples
        }
        let sampleCount = stats.sampleCount
        let sums = stats.sums
        let counts = stats.counts
        let cubeN = options.cubeSize
        let cubeCells = cubeN * cubeN * cubeN
        let dx = alignment.dx
        let dy = alignment.dy

        progress?(0.80, "Building cube…")

        // 8 + 9. Average + smooth + anchor empty cells to identity
        let cube = buildCube(
            sums: sums,
            counts: counts,
            size: cubeN,
            iterations: options.smoothingIterations
        )

        // Coverage: % of cells that received any direct samples
        var directlyFilled = 0
        for c in counts where c > 0 { directlyFilled += 1 }
        let coverage = Float(directlyFilled) / Float(cubeCells) * 100

        // Sharpening ratio with a small floor to avoid divide-by-zero
        let sharpRatio: Float
        if stats.rawHFEnergy > 1 {
            sharpRatio = Float(stats.jpgHFEnergy / stats.rawHFEnergy)
        } else {
            sharpRatio = 1
        }

        // Saturation ratio (smooth-region chroma)
        let satRatio: Float
        if stats.rawChromaSum > 0.001 {
            satRatio = Float(stats.jpgChromaSum / stats.rawChromaSum)
        } else {
            satRatio = 1
        }

        progress?(0.92, "Reading EXIF…")
        let cameraInfo = readCameraInfo(from: jpgURL)

        // Build tone curve points
        var tonePoints: [RecipeReport.ToneCurvePoint] = []
        let toneBins = stats.toneCounts.count
        for b in 0..<toneBins where stats.toneCounts[b] > 0 {
            let n = Float(stats.toneCounts[b])
            tonePoints.append(.init(
                input:   stats.toneSumIn[b] / n,
                outputR: stats.toneSumR[b]  / n,
                outputG: stats.toneSumG[b]  / n,
                outputB: stats.toneSumB[b]  / n
            ))
        }
        _ = sampleCount  // keep the local in scope for the report below
        _ = cubeCells

        let report = RecipeReport(
            toneCurve: tonePoints,
            saturationRatio: satRatio,
            sharpeningRatio: sharpRatio,
            sampleCount: sampleCount,
            cubeCoveragePercent: coverage,
            alignmentShift: (dx: dx, dy: dy),
            cameraInfo: cameraInfo
        )

        progress?(1.0, "Done")

        return Result(cube: cube, size: cubeN, report: report)
    }

    // MARK: - Sampling

    /// Accumulators returned by the inner sample loop. Lifted into a struct so
    /// the loop body can live in its own function (the type-checker can't
    /// handle 100+ lines of arithmetic in a single expression).
    private struct SampleStats {
        var sums: [SIMD3<Float>]
        var counts: [Int32]
        var sampleCount: Int
        var jpgChromaSum: Double
        var rawChromaSum: Double
        var jpgHFEnergy: Double
        var rawHFEnergy: Double
        var toneSumIn: [Float]
        var toneSumR: [Float]
        var toneSumG: [Float]
        var toneSumB: [Float]
        var toneCounts: [Int]
    }

    private static func runSampleLoop(
        rawBuf: ByteBuffer,
        jpgBuf: ByteBuffer,
        blurBuf: ByteBuffer,
        alignment: (dx: Int, dy: Int),
        options: Options
    ) -> SampleStats {
        let cubeN = options.cubeSize
        let cubeCells = cubeN * cubeN * cubeN
        let toneBins = 16

        var stats = SampleStats(
            sums:        [SIMD3<Float>](repeating: .zero, count: cubeCells),
            counts:      [Int32](repeating: 0, count: cubeCells),
            sampleCount: 0,
            jpgChromaSum: 0,
            rawChromaSum: 0,
            jpgHFEnergy: 0,
            rawHFEnergy: 0,
            toneSumIn:   [Float](repeating: 0, count: toneBins),
            toneSumR:    [Float](repeating: 0, count: toneBins),
            toneSumG:    [Float](repeating: 0, count: toneBins),
            toneSumB:    [Float](repeating: 0, count: toneBins),
            toneCounts:  [Int](repeating: 0, count: toneBins)
        )

        let width = rawBuf.width
        let height = rawBuf.height
        let bpr = rawBuf.bytesPerRow

        let dx = alignment.dx
        let dy = alignment.dy
        let xMin = max(0, -dx) + 1
        let xMax = min(width, width - dx) - 1
        let yMin = max(0, -dy) + 1
        let yMax = min(height, height - dy) - 1
        guard xMax > xMin, yMax > yMin else { return stats }

        // Open the three byte buffers once, then delegate the loop to a
        // top-level helper so the type-checker isn't asked to infer anything
        // through three nested closures + 80 lines of arithmetic.
        rawBuf.bytes.withUnsafeBufferPointer { rawBP in
            jpgBuf.bytes.withUnsafeBufferPointer { jpgBP in
                blurBuf.bytes.withUnsafeBufferPointer { blurBP in
                    accumulateSamples(
                        rawBase: rawBP.baseAddress!,
                        jpgBase: jpgBP.baseAddress!,
                        blurBase: blurBP.baseAddress!,
                        width: width,
                        bpr: bpr,
                        xMin: xMin, xMax: xMax,
                        yMin: yMin, yMax: yMax,
                        dx: dx, dy: dy,
                        cubeN: cubeN,
                        toneBins: toneBins,
                        options: options,
                        stats: &stats
                    )
                }
            }
        }

        return stats
    }

    /// Inner per-pixel sample loop. Lives at function scope (not nested in
    /// closures) so the Swift type checker has explicit types for every
    /// variable and doesn't try to infer through the surrounding closures.
    private static func accumulateSamples(
        rawBase: UnsafePointer<UInt8>,
        jpgBase: UnsafePointer<UInt8>,
        blurBase: UnsafePointer<UInt8>,
        width: Int,
        bpr: Int,
        xMin: Int, xMax: Int,
        yMin: Int, yMax: Int,
        dx: Int, dy: Int,
        cubeN: Int,
        toneBins: Int,
        options: Options,
        stats: inout SampleStats
    ) {
        let cubeNF = Float(cubeN - 1)
        let edgeThreshU8 = UInt8(min(255, max(1, Int(options.edgeThreshold * 255))))
        var rng = SystemRandomNumberGenerator()

        for _ in 0..<options.randomDrawCount {
            if stats.sampleCount >= options.samplesTarget { break }

            let x = Int.random(in: xMin..<xMax, using: &rng)
            let y = Int.random(in: yMin..<yMax, using: &rng)
            let off = y * bpr + x * 4

            let jr: UInt8 = jpgBase[off + 0]
            let jg: UInt8 = jpgBase[off + 1]
            let jb: UInt8 = jpgBase[off + 2]
            let br: UInt8 = blurBase[off + 0]
            let bg: UInt8 = blurBase[off + 1]
            let bb: UInt8 = blurBase[off + 2]

            let dRed: UInt8 = jr > br ? jr - br : br - jr
            let dGrn: UInt8 = jg > bg ? jg - bg : bg - jg
            let dBlu: UInt8 = jb > bb ? jb - bb : bb - jb
            let edge: UInt8 = max(dRed, max(dGrn, dBlu))

            // Sharpening estimator: every drawn pixel, edges included
            let edgeF = Float(edge)
            stats.jpgHFEnergy += Double(edgeF * edgeF)

            if edge > edgeThreshU8 { continue }

            // Read aligned neutral pixel
            let rawOff = (y + dy) * bpr + (x + dx) * 4
            let nr: UInt8 = rawBase[rawOff + 0]
            let ng: UInt8 = rawBase[rawOff + 1]
            let nb: UInt8 = rawBase[rawOff + 2]

            let nrF = Float(nr) / 255.0
            let ngF = Float(ng) / 255.0
            let nbF = Float(nb) / 255.0
            let cr = min(cubeN - 1, max(0, Int(nrF * cubeNF + 0.5)))
            let cg = min(cubeN - 1, max(0, Int(ngF * cubeNF + 0.5)))
            let cb = min(cubeN - 1, max(0, Int(nbF * cubeNF + 0.5)))
            let idx = cr + cg * cubeN + cb * cubeN * cubeN

            let jrF = Float(jr) / 255.0
            let jgF = Float(jg) / 255.0
            let jbF = Float(jb) / 255.0

            stats.sums[idx] += SIMD3<Float>(jrF, jgF, jbF)
            stats.counts[idx] += 1
            stats.sampleCount += 1

            // Tone-curve histogram
            let neutralLuma = (nrF + ngF + nbF) / 3
            let bin = min(toneBins - 1, max(0, Int(neutralLuma * Float(toneBins))))
            stats.toneSumIn[bin] += neutralLuma
            stats.toneSumR[bin]  += jrF
            stats.toneSumG[bin]  += jgF
            stats.toneSumB[bin]  += jbF
            stats.toneCounts[bin] += 1

            // Chroma (smooth-region saturation)
            let jLuma = (jrF + jgF + jbF) / 3
            let nChroma = sqrt((nrF - neutralLuma) * (nrF - neutralLuma) +
                               (ngF - neutralLuma) * (ngF - neutralLuma) +
                               (nbF - neutralLuma) * (nbF - neutralLuma))
            let jChroma = sqrt((jrF - jLuma) * (jrF - jLuma) +
                               (jgF - jLuma) * (jgF - jLuma) +
                               (jbF - jLuma) * (jbF - jLuma))
            stats.rawChromaSum += Double(nChroma)
            stats.jpgChromaSum += Double(jChroma)

            // Approximate raw HF energy from horizontal neighborhood
            if x > 0 && x < width - 1 {
                let l = Int(rawBase[rawOff - 4])
                let r = Int(rawBase[rawOff + 4])
                let d = abs(l - r)
                stats.rawHFEnergy += Double(d * d)
            }
        }
    }

    // MARK: - Internals

    private static func makeContext() -> CIContext {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        }
        return CIContext()
    }

    private static func lanczosScale(_ image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scaleX = size.width / extent.width
        let scaleY = size.height / extent.height
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = image
        lanczos.scale = Float(scaleY)
        lanczos.aspectRatio = Float(scaleX / scaleY)
        return lanczos.outputImage ?? image
    }

    private static func boxBlur(_ image: CIImage, radius: Float) -> CIImage {
        let blur = CIFilter.boxBlur()
        blur.inputImage = image
        blur.radius = radius
        // Box blur expands the extent; we'll crop back to the source rect
        // at the call site. Use clampedToExtent to avoid black edges.
        return image.clampedToExtent()
            .applyingFilter("CIBoxBlur", parameters: ["inputRadius": radius])
    }

    /// Render a CIImage into a contiguous RGBA8 byte buffer in sRGB.
    private static func render(
        _ image: CIImage,
        to rect: CGRect,
        context: CIContext,
        colorSpace: CGColorSpace
    ) -> ByteBuffer? {
        let width = Int(rect.width)
        let height = Int(rect.height)
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        bytes.withUnsafeMutableBytes { ptr in
            context.render(
                image,
                toBitmap: ptr.baseAddress!,
                rowBytes: bytesPerRow,
                bounds: rect,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return ByteBuffer(bytes: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    /// Brute-force ±radius integer-pixel alignment search using luma sum-of-products
    /// over a center patch. Fast enough — center patch is small.
    private static func computeAlignment(
        rawBuf: ByteBuffer,
        jpgBuf: ByteBuffer,
        radius: Int
    ) -> (dx: Int, dy: Int) {
        let w = rawBuf.width
        let h = rawBuf.height
        let p = min(256, min(w, h) / 4)
        let cx = w / 2
        let cy = h / 2

        // Pre-compute luma means in the center patch
        func patchLuma(_ buf: ByteBuffer, ox: Int, oy: Int) -> [Float] {
            var out = [Float](repeating: 0, count: p * p * 4)
            buf.withUnsafeBytes { ptr in
                let base = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                for j in 0..<(p * 2) {
                    let yy = cy - p + j + oy
                    if yy < 0 || yy >= h { continue }
                    for i in 0..<(p * 2) {
                        let xx = cx - p + i + ox
                        if xx < 0 || xx >= w { continue }
                        let off = yy * buf.bytesPerRow + xx * 4
                        let r = Float(base[off + 0])
                        let g = Float(base[off + 1])
                        let b = Float(base[off + 2])
                        out[j * (p * 2) + i] = (r + g + b) / 3
                    }
                }
            }
            // Center the values (subtract mean) for cross-correlation
            let mean = out.reduce(0, +) / Float(out.count)
            return out.map { $0 - mean }
        }

        let ref = patchLuma(jpgBuf, ox: 0, oy: 0)
        var bestScore: Float = -.greatestFiniteMagnitude
        var best = (dx: 0, dy: 0)
        for dy in -radius...radius {
            for dx in -radius...radius {
                let cmp = patchLuma(rawBuf, ox: dx, oy: dy)
                var sum: Float = 0
                for i in 0..<ref.count { sum += ref[i] * cmp[i] }
                if sum > bestScore {
                    bestScore = sum
                    best = (dx, dy)
                }
            }
        }
        return best
    }

    /// Average filled cells, smooth empty cells from neighbors, anchor leftovers
    /// to the identity cube.
    private static func buildCube(
        sums: [SIMD3<Float>],
        counts: [Int32],
        size: Int,
        iterations: Int
    ) -> [SIMD3<Float>] {
        let total = size * size * size
        var values = [SIMD3<Float>](repeating: .zero, count: total)
        var filled = [Bool](repeating: false, count: total)

        for i in 0..<total where counts[i] > 0 {
            values[i] = sums[i] / Float(counts[i])
            filled[i] = true
        }

        // Iterative pull-from-neighbors (3D Moore neighborhood)
        for _ in 0..<iterations {
            var newValues = values
            var newFilled = filled
            for b in 0..<size {
                for g in 0..<size {
                    for r in 0..<size {
                        let i = r + g * size + b * size * size
                        if filled[i] { continue }
                        var sum = SIMD3<Float>.zero
                        var n = 0
                        for db in -1...1 {
                            let nb = b + db
                            if nb < 0 || nb >= size { continue }
                            for dg in -1...1 {
                                let ng = g + dg
                                if ng < 0 || ng >= size { continue }
                                for dr in -1...1 {
                                    let nr = r + dr
                                    if nr < 0 || nr >= size { continue }
                                    if dr == 0 && dg == 0 && db == 0 { continue }
                                    let ni = nr + ng * size + nb * size * size
                                    if filled[ni] {
                                        sum += values[ni]
                                        n += 1
                                    }
                                }
                            }
                        }
                        if n > 0 {
                            newValues[i] = sum / Float(n)
                            newFilled[i] = true
                        }
                    }
                }
            }
            values = newValues
            filled = newFilled
        }

        // Anchor any still-unfilled cells to identity
        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let i = r + g * size + b * size * size
                    if !filled[i] {
                        values[i] = SIMD3<Float>(
                            Float(r) / denom,
                            Float(g) / denom,
                            Float(b) / denom
                        )
                    }
                }
            }
        }
        return values
    }

    /// Pull the EXIF tags we want for the report card. ImageIO doesn't decode
    /// Ricoh maker notes, so the proprietary "Image Control" name is absent —
    /// that's OK, the pixel-derived LUT is the actual output.
    private static func readCameraInfo(from url: URL) -> RecipeReport.CameraInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]

        let make = (tiff[kCGImagePropertyTIFFMake] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let model = (tiff[kCGImagePropertyTIFFModel] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let software = (tiff[kCGImagePropertyTIFFSoftware] as? String).map { $0.trimmingCharacters(in: .whitespaces) }

        // EXIF enums → human-readable strings
        func contrastLabel(_ v: Int?) -> String? {
            switch v { case 0: return "Normal"; case 1: return "Soft"; case 2: return "Hard"; default: return nil }
        }
        func saturationLabel(_ v: Int?) -> String? {
            switch v { case 0: return "Normal"; case 1: return "Low"; case 2: return "High"; default: return nil }
        }
        func sharpnessLabel(_ v: Int?) -> String? {
            switch v { case 0: return "Normal"; case 1: return "Soft"; case 2: return "Hard"; default: return nil }
        }
        func wbLabel(_ v: Int?) -> String? {
            switch v { case 0: return "Auto"; case 1: return "Manual"; default: return nil }
        }
        func customRenderedLabel(_ v: Int?) -> String? {
            switch v { case 0: return "Normal"; case 1: return "Custom"; default: return nil }
        }

        return RecipeReport.CameraInfo(
            make: make,
            model: model,
            software: software?.isEmpty == false ? software : nil,
            exifContrast: contrastLabel(exif[kCGImagePropertyExifContrast] as? Int),
            exifSaturation: saturationLabel(exif[kCGImagePropertyExifSaturation] as? Int),
            exifSharpness: sharpnessLabel(exif[kCGImagePropertyExifSharpness] as? Int),
            exifWhiteBalance: wbLabel(exif[kCGImagePropertyExifWhiteBalance] as? Int),
            exifCustomRendered: customRenderedLabel(exif[kCGImagePropertyExifCustomRendered] as? Int)
        )
    }
}

// MARK: - Byte buffer helper

/// Backing storage for a rendered RGBA8 image, with helpers for byte-level access.
private final class ByteBuffer {
    let bytes: [UInt8]
    let width: Int
    let height: Int
    let bytesPerRow: Int

    init(bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int) {
        self.bytes = bytes
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
    }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) -> R) -> R {
        return bytes.withUnsafeBytes { body($0) }
    }
}
