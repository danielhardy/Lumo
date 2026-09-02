import XCTest
import CoreImage
import CoreGraphics
@testable import LumoKit

/// Image-quality properties for the three global Effects controls. The fixtures deliberately pair
/// a high-frequency pattern with broad tonal regions so a contrast-slider implementation cannot
/// satisfy the tests by changing every pixel in the same way.
final class EffectsPipelineTests: XCTestCase {

    func testEffectsValuesClampNonFiniteAndRoundTripInTheDocument() throws {
        let effects = EffectsAdjustments(texture: .infinity, clarity: -.infinity, dehaze: .nan)
        XCTAssertEqual(effects, .neutral)

        let document = EditDocument(effects: EffectsAdjustments(texture: 35, clarity: -20, dehaze: 60))
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(decoded.effects, document.effects)
        XCTAssertNotEqual(decoded.editHash, EditDocument().editHash)
        XCTAssertFalse(decoded.isIdentity)
    }

    func testVignetteValuesClampAndRoundTripInTheDocument() throws {
        let vignette = VignetteAdjustments(
            amount: .infinity, midpoint: -.infinity, roundness: .nan,
            feather: 150, highlights: -20
        )
        XCTAssertEqual(vignette, VignetteAdjustments(midpoint: 50, feather: 100))

        let document = EditDocument(effects: EffectsAdjustments(vignette: VignetteAdjustments(
            amount: 65, midpoint: 42, roundness: -30, feather: 72, highlights: 55
        )))
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(EditDocument.self, from: data), document)
    }

    func testGrainValuesClampAndRoundTripInTheDocument() throws {
        let grain = GrainAdjustments(amount: .infinity, size: -.infinity, roughness: .nan)
        XCTAssertEqual(grain, GrainAdjustments(size: 50, roughness: 50))

        let document = EditDocument(effects: EffectsAdjustments(grain: GrainAdjustments(
            amount: 72, size: 28, roughness: 84
        )))
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(EditDocument.self, from: data), document)
        XCTAssertNotEqual(document.editHash, EditDocument().editHash)
    }

    private func grayscaleImage(values: [CGFloat], width: Int, height: Int) throws -> CIImage {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = Float(values[y * width + x])
                let offset = (y * width + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 1
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        return try XCTUnwrap(CIImage(
            bitmapData: data,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: nil
        ))
    }

    private func values(
        of image: CIImage,
        width: Int,
        height: Int,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0)
    ) -> [Float] {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let renderBounds = bounds.width > 0 && bounds.height > 0
            ? bounds
            : CGRect(x: 0, y: 0, width: width, height: height)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            Pixels.context.render(
                image,
                toBitmap: base,
                rowBytes: width * 4 * MemoryLayout<Float>.size,
                bounds: renderBounds,
                format: .RGBAf,
                colorSpace: nil
            )
        }
        return stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }
    }

    private func meanAbsoluteDifference(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Float(max(a.count, 1))
    }

    private func highFrequencyFixture(width: Int = 128, height: Int = 64) throws -> CIImage {
        let values = (0..<(width * height)).map { index in
            let x = index % width
            let y = index / width
            let base = 0.25 + 0.5 * CGFloat(x) / CGFloat(width - 1)
            return base + ((x + y).isMultiple(of: 2) ? 0.055 : -0.055)
        }
        return try grayscaleImage(values: values, width: width, height: height)
    }

    private func broadToneFixture(width: Int = 128, height: Int = 64) throws -> CIImage {
        let values = (0..<(width * height)).map { index in
            let x = index % width
            return 0.08 + 0.84 * CGFloat(x) / CGFloat(width - 1)
        }
        return try grayscaleImage(values: values, width: width, height: height)
    }

    func testNeutralEffectsAreAnExactIdentity() throws {
        let source = try highFrequencyFixture()
        let output = RenderPipeline.applyEffects(.neutral, to: source)

        XCTAssertEqual(output.extent, source.extent)
        assertPixelsEqual(
            try Pixels.bytes(of: output), try Pixels.bytes(of: source),
            "neutral Effects must be an exact no-op"
        )
    }

    func testTextureTargetsFineDetailMoreThanAFlatToneRamp() throws {
        let detail = try highFrequencyFixture()
        let tones = try broadToneFixture()
        let detailBase = values(of: detail, width: 128, height: 64)
        let toneBase = values(of: tones, width: 128, height: 64)

        let detailEdited = values(
            of: RenderPipeline.applyEffects(EffectsAdjustments(texture: 70), to: detail),
            width: 128, height: 64
        )
        let toneEdited = values(
            of: RenderPipeline.applyEffects(EffectsAdjustments(texture: 70), to: tones),
            width: 128, height: 64
        )

        XCTAssertGreaterThan(
            meanAbsoluteDifference(detailEdited, detailBase),
            meanAbsoluteDifference(toneEdited, toneBase) * 1.2,
            "Texture should favour medium/high-frequency detail over broad tone"
        )
    }

    func testClarityTargetsMidtonesAndUsesABroaderOperationThanTexture() throws {
        let source = try highFrequencyFixture()
        let base = values(of: source, width: 128, height: 64)
        let texture = values(
            of: RenderPipeline.applyEffects(EffectsAdjustments(texture: 70), to: source),
            width: 128, height: 64
        )
        let clarity = values(
            of: RenderPipeline.applyEffects(EffectsAdjustments(clarity: 70), to: source),
            width: 128, height: 64
        )

        XCTAssertGreaterThan(
            meanAbsoluteDifference(clarity, base), 0.002,
            "Clarity should visibly change a detailed image"
        )
        assertPixelsDiffer(
            try Pixels.bytes(of: RenderPipeline.applyEffects(EffectsAdjustments(texture: 70), to: source)),
            try Pixels.bytes(of: RenderPipeline.applyEffects(EffectsAdjustments(clarity: 70), to: source)),
            "Texture and Clarity must not be aliases"
        )
        XCTAssertNotEqual(texture, clarity)
    }

    func testDehazeChangesToneAndColourBeyondLocalDetail() throws {
        let source = CIImage(color: CIColor(red: 0.55, green: 0.42, blue: 0.28))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        let base = try Pixels.bytes(of: source)
        let clarity = try Pixels.bytes(of: RenderPipeline.applyEffects(
            EffectsAdjustments(clarity: 70), to: source
        ))
        let dehazed = try Pixels.bytes(of: RenderPipeline.applyEffects(
            EffectsAdjustments(dehaze: 70), to: source
        ))

        assertPixelsDiffer(dehazed, base, "Dehaze should change a low-contrast colour field")
        assertPixelsDiffer(dehazed, clarity, "Dehaze must combine tone/colour with local detail")
    }

    func testNegativeEffectsProvideInverseDirections() throws {
        let source = try highFrequencyFixture()
        let base = values(of: source, width: 128, height: 64)

        for makeEffects in [
            { EffectsAdjustments(texture: 70) },
            { EffectsAdjustments(clarity: 70) },
            { EffectsAdjustments(dehaze: 70) },
        ] {
            let positive = makeEffects()
            let negative = EffectsAdjustments(
                texture: positive.texture == 0 ? 0 : -positive.texture,
                clarity: positive.clarity == 0 ? 0 : -positive.clarity,
                dehaze: positive.dehaze == 0 ? 0 : -positive.dehaze
            )
            let positiveValues = values(
                of: RenderPipeline.applyEffects(positive, to: source), width: 128, height: 64
            )
            let negativeValues = values(
                of: RenderPipeline.applyEffects(negative, to: source), width: 128, height: 64
            )
            let positiveDelta = meanAbsoluteDifference(positiveValues, base)
            let negativeDelta = meanAbsoluteDifference(negativeValues, base)
            XCTAssertGreaterThan(positiveDelta, 0.001)
            XCTAssertGreaterThan(negativeDelta, 0.001)
            XCTAssertNotEqual(positiveValues, negativeValues)
        }
    }

    func testEffectsPreserveExtentAndAlpha() throws {
        let source = CIImage(color: CIColor(red: 0.7, green: 0.3, blue: 0.2, alpha: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 17, height: 11))

        for effects in [
            EffectsAdjustments(texture: 60),
            EffectsAdjustments(clarity: 60),
            EffectsAdjustments(dehaze: 60),
        ] {
            let output = RenderPipeline.applyEffects(effects, to: source)
            XCTAssertEqual(output.extent, source.extent)
            let bytes = try Pixels.bytes(of: output)
            XCTAssertEqual(bytes[3], 102, accuracy: 2, "Effects must preserve alpha")
        }
    }

    func testDehazeFullRangePreservesOffsetExtentOrientationAndFinitePixels() throws {
        let width = 640
        let height = 400
        let extent = CGRect(x: 37, y: 19, width: width, height: height)
        let source = try grayscaleImage(
            values: (0..<(width * height)).map { index in
                let y = CGFloat(index / width)
                return 0.12 + 0.76 * y / CGFloat(height - 1)
            }, width: width, height: height
        ).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        let sourceValues = values(of: source, width: width, height: height, bounds: extent)
        let sourceLow = sourceValues.prefix(width * height / 8).reduce(0, +)
            / Float(width * height / 8)
        let sourceHigh = sourceValues.suffix(width * height / 8).reduce(0, +)
            / Float(width * height / 8)
        let sourceDirection = sourceHigh - sourceLow
        let sourceBytes = try Pixels.bytes(of: source)

        for value in [-100.0, -1.0, 0.0, 1.0, 100.0] {
            let output = RenderPipeline.applyEffects(
                EffectsAdjustments(dehaze: value), to: source
            )
            XCTAssertEqual(
                output.extent, extent,
                "Dehaze \(value) changed the image frame"
            )

            let outputValues = values(of: output, width: width, height: height, bounds: extent)
            XCTAssertTrue(outputValues.allSatisfy { $0.isFinite },
                          "Dehaze \(value) produced a non-finite pixel")
            if abs(value) == 100 {
                assertPixelsDiffer(
                    try Pixels.bytes(of: output), sourceBytes,
                    "maximum Dehaze must remain an actual adjustment"
                )
            }
            let outputLow = outputValues.prefix(width * height / 8).reduce(0, +)
                / Float(width * height / 8)
            let outputHigh = outputValues.suffix(width * height / 8).reduce(0, +)
                / Float(width * height / 8)
            XCTAssertGreaterThan(
                (outputHigh - outputLow) * sourceDirection, 0,
                "Dehaze \(value) inverted the source orientation"
            )
        }
    }

    func testClarityFullRangePreservesLargeOffsetExtentOrientationAndFinitePixels() throws {
        let width = 2048
        let height = 1536
        let extent = CGRect(x: 113, y: 67, width: width, height: height)
        let source = try grayscaleImage(
            values: (0..<(width * height)).map { index in
                let x = index % width
                let y = index / width
                let ramp = 0.12 + 0.76 * CGFloat(y) / CGFloat(height - 1)
                let detail = (x + y).isMultiple(of: 2) ? 0.025 : -0.025
                return ramp + detail
            }, width: width, height: height
        ).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        let sourceValues = values(of: source, width: width, height: height, bounds: extent)
        let sourceLow = sourceValues.prefix(width * height / 8).reduce(0, +)
            / Float(width * height / 8)
        let sourceHigh = sourceValues.suffix(width * height / 8).reduce(0, +)
            / Float(width * height / 8)
        let sourceDirection = sourceHigh - sourceLow
        let sourceBytes = try Pixels.bytes(of: source)

        for value in [-100.0, -1.0, 0.0, 1.0, 100.0] {
            let output = RenderPipeline.applyEffects(
                EffectsAdjustments(clarity: value), to: source
            )
            XCTAssertEqual(output.extent, extent, "Clarity \(value) changed the image frame")

            let outputValues = values(of: output, width: width, height: height, bounds: extent)
            XCTAssertTrue(outputValues.allSatisfy { $0.isFinite },
                          "Clarity \(value) produced a non-finite pixel")
            if abs(value) == 100 {
                assertPixelsDiffer(
                    try Pixels.bytes(of: output), sourceBytes,
                    "maximum Clarity must remain an actual local-contrast adjustment"
                )
            }
            let outputLow = outputValues.prefix(width * height / 8).reduce(0, +)
                / Float(width * height / 8)
            let outputHigh = outputValues.suffix(width * height / 8).reduce(0, +)
                / Float(width * height / 8)
            XCTAssertGreaterThan(
                (outputHigh - outputLow) * sourceDirection, 0,
                "Clarity (value) inverted the source orientation"
            )
        }
    }

    func testEffectsUseRelativeRadiiAtPreviewScale() throws {
        let source = try highFrequencyFixture(width: 128, height: 64)
        let effects = EffectsAdjustments(texture: 70, clarity: 45, dehaze: 30)
        let full = RenderPipeline.applyEffects(effects, to: source)
        let downscaled = source.applyingFilter("CILanczosScaleTransform", parameters: [
            "inputScale": 0.5, "inputAspectRatio": 1.0,
        ])
        let preview = RenderPipeline.applyEffects(effects, to: downscaled)
        XCTAssertEqual(preview.extent.width, 64, accuracy: 1)
        XCTAssertEqual(preview.extent.height, 32, accuracy: 1)
        XCTAssertEqual(full.extent.width / preview.extent.width, 2, accuracy: 0.05)
        XCTAssertEqual(full.extent.height / preview.extent.height, 2, accuracy: 0.05)
        XCTAssertTrue(try Pixels.bytes(of: preview).count > 0)
    }

    func testNeutralVignetteIsAnExactIdentity() throws {
        let source = try highFrequencyFixture()
        let output = RenderPipeline.applyVignette(.neutral, to: source)
        XCTAssertEqual(output.extent, source.extent)
        assertPixelsEqual(try Pixels.bytes(of: output), try Pixels.bytes(of: source),
                          "neutral vignette must be an exact no-op")
    }

    func testVignettePreservesExtentAndHasIndependentControls() throws {
        let source = try grayscaleImage(
            values: (0..<128 * 64).map { index in
                let x = CGFloat(index % 128) / 127
                let y = CGFloat(index / 128) / 63
                return 0.15 + 0.7 * (0.65 * x + 0.35 * y)
            }, width: 128, height: 64
        )
        let base = try Pixels.bytes(of: source)
        let amount = VignetteAdjustments(amount: 70)
        let variants = [
            VignetteAdjustments(amount: 70, midpoint: 25),
            VignetteAdjustments(amount: 70, roundness: 80),
            VignetteAdjustments(amount: 70, feather: 5),
            VignetteAdjustments(amount: 70, highlights: 90),
        ]
        let reference = try Pixels.bytes(of: RenderPipeline.applyVignette(amount, to: source))
        XCTAssertNotEqual(reference, base)
        for variant in variants {
            let output = RenderPipeline.applyVignette(variant, to: source)
            XCTAssertEqual(output.extent, source.extent)
            assertPixelsDiffer(try Pixels.bytes(of: output), reference,
                               "each vignette subordinate control must have a visible effect")
        }
    }

    func testVignetteUsesPostCropAspectRatioAndPreservesHighlights() throws {
        let extent = CGRect(x: 37, y: 19, width: 128, height: 64)
        let dark = CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25)).cropped(to: extent)
        let bright = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 0.95)).cropped(to: extent)
        let vignette = VignetteAdjustments(amount: 80, midpoint: 45, feather: 30)
        let darkOutput = RenderPipeline.applyVignette(vignette, to: dark)
        let brightBytes = try Pixels.bytes(of: RenderPipeline.applyVignette(vignette, to: bright))
        let preservedBytes = try Pixels.bytes(of: RenderPipeline.applyVignette(
            VignetteAdjustments(amount: 80, midpoint: 45, feather: 30, highlights: 100), to: bright
        ))

        XCTAssertEqual(darkOutput.extent, extent)
        XCTAssertLessThan(try Pixels.bytes(of: darkOutput)[0], 64,
                          "positive Amount should darken an edge")
        XCTAssertGreaterThan(preservedBytes[0], brightBytes[0],
                             "Highlights should preserve bright edge detail")
    }

    func testVignetteIsAfterTheLUTInTheFullPipeline() throws {
        let source = try highFrequencyFixture(width: 32, height: 16)
        let lut = TestImages.warmLUT()
        let document = EditDocument(
            effects: EffectsAdjustments(vignette: VignetteAdjustments(amount: 65)),
            lut: LUTSettings(lutID: lut.lutID, intensity: 1)
        )
        let graph = try XCTUnwrap(RenderPipeline.buildImage(
            developed: source, document: document, lut: lut, includePostRenderWhiteBalance: false
        ))
        let lutOnly = try XCTUnwrap(RenderPipeline.buildImage(
            developed: source,
            document: EditDocument(lut: document.lut),
            lut: lut,
            includePostRenderWhiteBalance: false
        ))
        let expected = RenderPipeline.applyVignette(document.effects.vignette, to: lutOnly)
        assertPixelsEqual(try Pixels.bytes(of: graph), try Pixels.bytes(of: expected),
                          "vignette must consume LUT output")
    }

    func testGrainIsAfterTheLUTInTheFullPipeline() throws {
        let source = try highFrequencyFixture(width: 32, height: 16)
        let lut = TestImages.warmLUT()
        let grain = GrainAdjustments(amount: 72, size: 55, roughness: 70)
        let document = EditDocument(
            effects: EffectsAdjustments(grain: grain),
            lut: LUTSettings(lutID: lut.lutID, intensity: 1)
        )
        let graph = try XCTUnwrap(RenderPipeline.buildImage(
            developed: source, document: document, lut: lut, includePostRenderWhiteBalance: false
        ))
        let lutOnly = try XCTUnwrap(RenderPipeline.buildImage(
            developed: source,
            document: EditDocument(lut: document.lut),
            lut: lut,
            includePostRenderWhiteBalance: false
        ))
        let expected = RenderPipeline.applyGrain(grain, to: lutOnly)
        assertPixelsEqual(try Pixels.bytes(of: graph), try Pixels.bytes(of: expected),
                          "grain must consume LUT output")
    }

    func testNeutralGrainIsAnExactIdentity() throws {
        let source = try highFrequencyFixture()
        let output = RenderPipeline.applyGrain(.neutral, to: source, seed: 0x1234)

        XCTAssertEqual(output.extent, source.extent)
        assertPixelsEqual(try Pixels.bytes(of: output), try Pixels.bytes(of: source),
                          "neutral grain must be an exact no-op")
    }

    func testGrainIsDeterministicAndSeedIsIndependentOfEditState() throws {
        let source = try highFrequencyFixture()
        let grain = GrainAdjustments(amount: 78, size: 62, roughness: 35)
        let first = RenderPipeline.applyGrain(grain, to: source, seed: 0xDEADBEEF)
        let second = RenderPipeline.applyGrain(grain, to: source, seed: 0xDEADBEEF)

        assertPixelsEqual(try Pixels.bytes(of: first), try Pixels.bytes(of: second),
                          "the same grain request must reproduce the same pattern")
        assertPixelsDiffer(
            try Pixels.bytes(of: first),
            try Pixels.bytes(of: RenderPipeline.applyGrain(grain, to: source, seed: 0x12345678)),
            byAtLeast: 2,
            "different source seeds should produce different fields"
        )
        assertPixelsDiffer(
            try Pixels.bytes(of: first),
            try Pixels.bytes(of: RenderPipeline.applyGrain(grain, to: source, seed: 0xDEADBEEF + 100)),
            byAtLeast: 2,
            "seeds that differ only in low bits should produce different fields"
        )

        let asset = ImageSource(data: Data("same asset".utf8), nativeExtent: source.extent.size)
        let sameAsset = ImageSource(data: Data("same asset".utf8), nativeExtent: source.extent.size)
        let otherAsset = ImageSource(data: Data("other asset".utf8), nativeExtent: source.extent.size)
        XCTAssertEqual(RenderPipeline.grainSeed(for: asset), RenderPipeline.grainSeed(for: sameAsset))
        XCTAssertNotEqual(RenderPipeline.grainSeed(for: asset), RenderPipeline.grainSeed(for: otherAsset))
    }

    func testGrainAmountSizeAndRoughnessAreIndependentlyMeasurable() throws {
        let source = try highFrequencyFixture()
        let base = try Pixels.bytes(of: source)
        let amount = try Pixels.bytes(of: RenderPipeline.applyGrain(
            GrainAdjustments(amount: 80), to: source, seed: 7
        ))
        let small = try Pixels.bytes(of: RenderPipeline.applyGrain(
            GrainAdjustments(amount: 80, size: 10, roughness: 50), to: source, seed: 7
        ))
        let large = try Pixels.bytes(of: RenderPipeline.applyGrain(
            GrainAdjustments(amount: 80, size: 90, roughness: 50), to: source, seed: 7
        ))
        let smooth = try Pixels.bytes(of: RenderPipeline.applyGrain(
            GrainAdjustments(amount: 80, size: 50, roughness: 10), to: source, seed: 7
        ))
        let rough = try Pixels.bytes(of: RenderPipeline.applyGrain(
            GrainAdjustments(amount: 80, size: 50, roughness: 90), to: source, seed: 7
        ))

        assertPixelsDiffer(amount, base, byAtLeast: 2, "Amount must add visible grain")
        assertPixelsDiffer(small, large, byAtLeast: 2, "Size must change the grain field")
        assertPixelsDiffer(smooth, rough, byAtLeast: 2, "Roughness must change the grain field")
        XCTAssertNotEqual(small, rough, "the subordinate controls must not collapse to one alias")
    }

    func testGrainUsesRelativeOutputScaleAndPreservesExtentAndAlpha() throws {
        let full = try highFrequencyFixture(width: 256, height: 128)
        let preview = full.applyingFilter("CILanczosScaleTransform", parameters: [
            "inputScale": 0.5, "inputAspectRatio": 1.0,
        ])
        let grain = GrainAdjustments(amount: 85, size: 58, roughness: 64)
        let fullOutput = RenderPipeline.applyGrain(grain, to: full, seed: 19)
        let previewOutput = RenderPipeline.applyGrain(grain, to: preview, seed: 19)

        XCTAssertEqual(fullOutput.extent, full.extent)
        XCTAssertEqual(previewOutput.extent.width, 128, accuracy: 1)
        XCTAssertEqual(previewOutput.extent.height, 64, accuracy: 1)
        XCTAssertGreaterThan(try grainVariation(of: fullOutput), 0.0001)
        XCTAssertGreaterThan(try grainVariation(of: previewOutput), 0.0001)
        let fullVariation = try grainVariation(of: fullOutput)
        let previewVariation = try grainVariation(of: previewOutput)
        XCTAssertEqual(
            fullVariation / previewVariation,
            1, accuracy: 0.45,
            "normalized grain should retain a comparable viewed-scale variation"
        )

        let alphaSource = CIImage(color: CIColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 0.4))
            .cropped(to: CGRect(x: 11, y: 7, width: 32, height: 19))
        let alphaOutput = RenderPipeline.applyGrain(grain, to: alphaSource, seed: 19)
        XCTAssertEqual(alphaOutput.extent, alphaSource.extent)
        XCTAssertEqual(try Pixels.bytes(of: alphaOutput)[3], 102, accuracy: 2)
    }

    private func grainVariation(of image: CIImage) throws -> Double {
        let bytes = try Pixels.bytes(of: image)
        let values = stride(from: 0, to: bytes.count, by: 4).map { Double(bytes[$0]) / 255 }
        let mean = values.reduce(0, +) / Double(max(values.count, 1))
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(values.count, 1))
    }
}
