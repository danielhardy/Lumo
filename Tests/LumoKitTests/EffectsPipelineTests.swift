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

    private func values(of image: CIImage, width: Int, height: Int) -> [Float] {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            Pixels.context.render(
                image,
                toBitmap: base,
                rowBytes: width * 4 * MemoryLayout<Float>.size,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
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
}
