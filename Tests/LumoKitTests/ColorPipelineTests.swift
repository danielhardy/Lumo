import XCTest
import CoreImage
import CoreGraphics
@testable import LumoKit

/// Image-quality properties for the global Color stage. The fixture intentionally mixes a skin-like
/// swatch, foliage, a saturated primary, and a neutral so a uniform saturation multiplier cannot
/// accidentally masquerade as vibrance.
final class ColorPipelineTests: XCTestCase {

    private let swatches: [(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)] = [
        (0.72, 0.42, 0.30, 1), // skin-like
        (0.20, 0.65, 0.18, 1), // foliage-like
        (0.95, 0.05, 0.04, 1), // already saturated
        (0.45, 0.45, 0.45, 1), // neutral
    ]

    private func swatchImage() throws -> CIImage {
        let width = swatches.count
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt8](repeating: 0, count: width * 4)
        for (index, swatch) in swatches.enumerated() {
            pixels[index * 4] = UInt8(swatch.r * 255)
            pixels[index * 4 + 1] = UInt8(swatch.g * 255)
            pixels[index * 4 + 2] = UInt8(swatch.b * 255)
            pixels[index * 4 + 3] = UInt8(swatch.a * 255)
        }
        let data = Data(pixels)
        return try XCTUnwrap(CIImage(
            bitmapData: data,
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: 1),
            format: .RGBA8,
            colorSpace: space
        ))
    }

    private func pixel(_ bytes: [UInt8], at index: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let offset = index * 4
        return (
            Int(bytes[offset]), Int(bytes[offset + 1]),
            Int(bytes[offset + 2]), Int(bytes[offset + 3])
        )
    }

    private func chroma(_ pixel: (r: Int, g: Int, b: Int, a: Int)) -> Int {
        max(pixel.r, pixel.g, pixel.b) - min(pixel.r, pixel.g, pixel.b)
    }

    private func floatValues(of image: CIImage) throws -> [Float] {
        let rect = image.extent.integral
        var values = [Float](repeating: 0, count: Int(rect.width * rect.height) * 4)
        values.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            Pixels.context.render(
                image, toBitmap: base,
                rowBytes: Int(rect.width) * 4 * MemoryLayout<Float>.size,
                bounds: rect, format: .RGBAf, colorSpace: nil
            )
        }
        return values
    }

    func testNeutralColorIsAnExactNoOpAndPreservesAlpha() throws {
        let source = try swatchImage()
        let original = try Pixels.bytes(of: source)
        let rendered = try Pixels.bytes(of: RenderPipeline.applyColor(.neutral, to: source))

        assertPixelsEqual(rendered, original, "neutral Color must be an exact no-op")
        for index in swatches.indices {
            XCTAssertEqual(pixel(rendered, at: index).a, Int(swatches[index].a * 255), accuracy: 1)
        }
    }

    func testSaturationMinus100ProducesNearMonochromeSwatches() throws {
        let source = try swatchImage()
        let rendered = try Pixels.bytes(of: RenderPipeline.applyColor(
            ColorAdjustments(saturation: -100), to: source
        ))

        for index in 0..<3 {
            XCTAssertLessThanOrEqual(
                chroma(pixel(rendered, at: index)), 3,
                "Saturation -100 should be near-monochrome for swatch \(index)"
            )
        }
    }

    func testVibranceAndSaturationHaveDistinctBehaviorOnMixedChromaInput() throws {
        let source = try swatchImage()
        let base = try Pixels.bytes(of: source)
        let saturated = try Pixels.bytes(of: RenderPipeline.applyColor(
            ColorAdjustments(saturation: 60), to: source
        ))
        let vibrant = try Pixels.bytes(of: RenderPipeline.applyColor(
            ColorAdjustments(vibrance: 60), to: source
        ))

        assertPixelsDiffer(saturated, vibrant, "Vibrance and Saturation must not be aliases")

        let saturatedPrimary = 2
        let saturationDelta = abs(chroma(pixel(saturated, at: saturatedPrimary))
                                  - chroma(pixel(base, at: saturatedPrimary)))
        let vibranceDelta = abs(chroma(pixel(vibrant, at: saturatedPrimary))
                                - chroma(pixel(base, at: saturatedPrimary)))
        XCTAssertLessThan(
            vibranceDelta, saturationDelta,
            "Vibrance should protect an already-saturated primary better than Saturation"
        )
    }

    func testColorExtremesRemainFiniteAndBounded() throws {
        let source = try swatchImage()
        for color in [
            ColorAdjustments(vibrance: -100), ColorAdjustments(vibrance: 100),
            ColorAdjustments(saturation: -100), ColorAdjustments(saturation: 100),
            ColorAdjustments(vibrance: 100, saturation: 100),
        ] {
            let rendered = RenderPipeline.applyColor(color, to: source)
            XCTAssertTrue(
                try floatValues(of: rendered).allSatisfy(\.isFinite),
                "Color output must not contain NaN or infinity at \(color)"
            )
            let bytes = try Pixels.bytes(of: rendered)
            for index in swatches.indices {
                XCTAssertEqual(pixel(bytes, at: index).a, Int(swatches[index].a * 255), accuracy: 1)
            }
        }
    }

    func testColorFiltersPreserveTransparentPixelAlpha() throws {
        let source = CIImage(color: CIColor(red: 0.7, green: 0.3, blue: 0.2, alpha: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let original = try Pixels.bytes(of: source)

        for color in [ColorAdjustments(vibrance: 60), ColorAdjustments(saturation: -60)] {
            let rendered = try Pixels.bytes(of: RenderPipeline.applyColor(color, to: source))
            XCTAssertEqual(rendered[3], original[3], "Color controls must preserve alpha")
        }
    }

    func testGlobalColorReachesTheSharedRenderGraph() throws {
        let source = try swatchImage()
        let neutral = RenderPipeline.buildImage(
            developed: source, document: EditDocument(), lut: nil
        )
        let desaturated = RenderPipeline.buildImage(
            developed: source,
            document: EditDocument(color: ColorAdjustments(saturation: -100)),
            lut: nil
        )

        assertPixelsDiffer(
            try Pixels.bytes(of: neutral), try Pixels.bytes(of: desaturated),
            "global Color controls must reach the shared render graph"
        )
    }
}
