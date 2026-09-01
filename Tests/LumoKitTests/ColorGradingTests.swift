import XCTest
import CoreImage
import CoreGraphics
@testable import LumoKit

final class ColorGradingTests: XCTestCase {

    private let levels: [CGFloat] = [0.12, 0.28, 0.50, 0.72, 0.88]

    private func image(levels: [CGFloat]) throws -> CIImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt8]()
        for level in levels {
            let value = UInt8(level * 255)
            pixels += [value, value, value, 255]
        }
        return try XCTUnwrap(CIImage(
            bitmapData: Data(pixels),
            bytesPerRow: levels.count * 4,
            size: CGSize(width: levels.count, height: 1),
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
        max(pixel.r, max(pixel.g, pixel.b)) - min(pixel.r, min(pixel.g, pixel.b))
    }

    private func effect(_ edited: [UInt8], versus base: [UInt8], at index: Int) -> Int {
        let editedPixel = pixel(edited, at: index)
        let basePixel = pixel(base, at: index)
        return abs(editedPixel.r - basePixel.r)
            + abs(editedPixel.g - basePixel.g)
            + abs(editedPixel.b - basePixel.b)
    }

    func testModelRoundTripsDefaultsAndClamps() throws {
        let grading = ColorGradingAdjustments(
            shadows: ColorGradingWheel(hue: 220, saturation: 35),
            midtones: ColorGradingWheel(hue: 45, saturation: 12),
            highlights: ColorGradingWheel(hue: 10, saturation: 28),
            blending: 73,
            balance: -24
        )
        let color = ColorAdjustments(grading: grading)
        let decoded = try JSONDecoder().decode(
            ColorAdjustments.self, from: JSONEncoder().encode(color)
        )
        XCTAssertEqual(decoded, color)
        XCTAssertEqual(ColorGradingAdjustments.neutral.blending, 50)
        XCTAssertEqual(ColorGradingAdjustments.neutral.balance, 0)
        XCTAssertTrue(ColorGradingWheel(hue: 300, saturation: 0).isIdentity)

        var clamped = ColorGradingAdjustments(
            shadows: ColorGradingWheel(hue: .infinity, saturation: -.infinity),
            blending: .nan,
            balance: .infinity
        )
        XCTAssertEqual(clamped.shadows, .neutral)
        XCTAssertEqual(clamped.blending, 50)
        XCTAssertEqual(clamped.balance, 0)
        clamped.highlights = ColorGradingWheel(hue: 500, saturation: 120)
        XCTAssertEqual(clamped.highlights, ColorGradingWheel(hue: 360, saturation: 100))
    }

    func testMissingGradingMigratesToNeutral() throws {
        let oldColor = try JSONDecoder().decode(
            ColorAdjustments.self, from: Data("{\"vibrance\":0,\"saturation\":0}".utf8)
        )
        XCTAssertEqual(oldColor.grading, .neutral)
        XCTAssertTrue(oldColor.isIdentity)
    }

    func testWheelMappingReachesNeutralRimAndEveryCardinalHue() {
        XCTAssertEqual(ColorGradingWheelMapping.wheel(at: .init(x: 0, y: 0)), .neutral)
        XCTAssertEqual(ColorGradingWheelMapping.wheel(at: .init(x: 1, y: 0)),
                       ColorGradingWheel(hue: 0, saturation: 100))
        XCTAssertEqual(ColorGradingWheelMapping.wheel(at: .init(x: 0, y: 1)),
                       ColorGradingWheel(hue: 90, saturation: 100))
        XCTAssertEqual(ColorGradingWheelMapping.wheel(at: .init(x: -1, y: 0)),
                       ColorGradingWheel(hue: 180, saturation: 100))
        XCTAssertEqual(ColorGradingWheelMapping.wheel(at: .init(x: 0, y: -1)),
                       ColorGradingWheel(hue: 270, saturation: 100))
        XCTAssertEqual(ColorGradingWheelMapping.wheel(at: .init(x: 4, y: 0)),
                       ColorGradingWheel(hue: 0, saturation: 100),
                       "a drag beyond the rim must still reach the maximum grade")
    }

    func testWheelMappingRoundTripsStoredValuesAndAccessibilityAdjustments() {
        let original = ColorGradingWheel(hue: 217.25, saturation: 43.5)
        let point = ColorGradingWheelMapping.point(for: original)
        let restored = ColorGradingWheelMapping.wheel(at: point)

        XCTAssertEqual(restored.hue, original.hue, accuracy: 1e-12)
        XCTAssertEqual(restored.saturation, original.saturation, accuracy: 1e-12)
        XCTAssertEqual(
            ColorGradingWheelMapping.accessibilityValue(for: original),
            "Hue 217 degrees, Saturation 44 percent"
        )
        XCTAssertEqual(
            ColorGradingWheelMapping.adjustingSaturation(
                ColorGradingWheel(hue: 10, saturation: 98), by: ColorGradingWheelMapping.accessibilityStep
            ),
            ColorGradingWheel(hue: 10, saturation: 100)
        )
    }

    func testZeroSaturationAcrossWheelsIsExactIdentityRegardlessOfHue() throws {
        let source = try image(levels: levels)
        let grading = ColorGradingAdjustments(
            shadows: ColorGradingWheel(hue: 220),
            midtones: ColorGradingWheel(hue: 45),
            highlights: ColorGradingWheel(hue: 10),
            blending: 100,
            balance: -100
        )
        XCTAssertTrue(grading.isIdentity)
        let original = try Pixels.bytes(of: source)
        let rendered = try Pixels.bytes(of: RenderPipeline.applyColorGrading(grading, to: source))
        assertPixelsEqual(rendered, original, "zero-saturation grading must be an exact no-op")
    }

    func testEachWheelPredominantlyAffectsItsTonalRegion() throws {
        let source = try image(levels: levels)
        let base = try Pixels.bytes(of: source)
        let wheelAdjustments: [ColorGradingWheel] = [
            ColorGradingWheel(hue: 220, saturation: 70),
            ColorGradingWheel(hue: 120, saturation: 70),
            ColorGradingWheel(hue: 10, saturation: 70),
        ]
        let intendedIndices = [0, 2, 4]

        for (wheelIndex, wheel) in wheelAdjustments.enumerated() {
            let grading: ColorGradingAdjustments
            switch wheelIndex {
            case 0: grading = ColorGradingAdjustments(shadows: wheel, blending: 0)
            case 1: grading = ColorGradingAdjustments(midtones: wheel, blending: 0)
            default: grading = ColorGradingAdjustments(highlights: wheel, blending: 0)
            }
            let edited = try Pixels.bytes(of: RenderPipeline.applyColorGrading(grading, to: source))
            let intended = effect(edited, versus: base, at: intendedIndices[wheelIndex])
            let remoteIndex = wheelIndex == 0 ? 4 : 0
            let remote = effect(edited, versus: base, at: remoteIndex)
            XCTAssertGreaterThan(intended, remote,
                                 "wheel \(wheelIndex) should primarily affect its tonal region (intended=\(intended), remote=\(remote))")
        }
    }

    func testBlendingAndBalanceHaveIndependentMonotonicEffects() throws {
        let source = try image(levels: [0.34, 0.50, 0.66])
        let base = try Pixels.bytes(of: source)
        let shadowWheel = ColorGradingWheel(hue: 220, saturation: 80)

        let narrow = try Pixels.bytes(of: RenderPipeline.applyColorGrading(
            ColorGradingAdjustments(shadows: shadowWheel, blending: 0), to: source
        ))
        let broad = try Pixels.bytes(of: RenderPipeline.applyColorGrading(
            ColorGradingAdjustments(shadows: shadowWheel, blending: 100), to: source
        ))
        XCTAssertGreaterThan(effect(broad, versus: base, at: 1), effect(narrow, versus: base, at: 1),
                             "blending should widen the shadow overlap")

        let negative = try Pixels.bytes(of: RenderPipeline.applyColorGrading(
            ColorGradingAdjustments(shadows: shadowWheel, balance: -100), to: source
        ))
        let positive = try Pixels.bytes(of: RenderPipeline.applyColorGrading(
            ColorGradingAdjustments(shadows: shadowWheel, balance: 100), to: source
        ))
        XCTAssertGreaterThan(effect(negative, versus: base, at: 1), effect(positive, versus: base, at: 1),
                             "negative balance should favor shadows independently")
        XCTAssertNotEqual(narrow, negative, "blending and balance must not alias one another")
    }

    func testSmoothGrayscaleGradientHasNoVisibleDiscontinuity() throws {
        let gradientLevels = stride(from: 0.01, through: 0.99, by: 0.01).map { CGFloat($0) }
        let source = try image(levels: gradientLevels)
        let grading = ColorGradingAdjustments(
            shadows: ColorGradingWheel(hue: 220, saturation: 75),
            midtones: ColorGradingWheel(hue: 35, saturation: 55),
            highlights: ColorGradingWheel(hue: 10, saturation: 65),
            blending: 100,
            balance: 18
        )
        let rendered = try Pixels.bytes(of: RenderPipeline.applyColorGrading(grading, to: source))

        for index in 1..<(gradientLevels.count - 1) {
            let before = pixel(rendered, at: index - 1)
            let current = pixel(rendered, at: index)
            let after = pixel(rendered, at: index + 1)
            XCTAssertLessThanOrEqual(abs(current.r - before.r), 28)
            XCTAssertLessThanOrEqual(abs(current.g - before.g), 28)
            XCTAssertLessThanOrEqual(abs(current.b - before.b), 28)
            XCTAssertLessThanOrEqual(abs(after.r - current.r), 28)
            XCTAssertLessThanOrEqual(abs(after.g - current.g), 28)
            XCTAssertLessThanOrEqual(abs(after.b - current.b), 28)
        }
    }

    func testGradingReachesSharedGraph() throws {
        let source = try image(levels: [0.2, 0.5, 0.8])
        let grading = ColorGradingAdjustments(
            midtones: ColorGradingWheel(hue: 120, saturation: 65)
        )
        let neutral = RenderPipeline.buildImage(
            developed: source, document: EditDocument(), lut: nil
        )
        let graded = RenderPipeline.buildImage(
            developed: source,
            document: EditDocument(color: ColorAdjustments(grading: grading)),
            lut: nil
        )
        assertPixelsDiffer(
            try Pixels.bytes(of: neutral), try Pixels.bytes(of: graded),
            "grading state must reach the shared render graph"
        )
    }
}
