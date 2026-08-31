import XCTest
import CoreImage
import CoreGraphics
@testable import LumoKit

final class ColorMixerTests: XCTestCase {

    private let hues: [CGFloat] = [0, 30, 60, 120, 180, 240, 270, 300]

    private func image(hues: [CGFloat]) throws -> CIImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt8]()
        for hue in hues {
            let (red, green, blue) = rgb(hue: hue, saturation: 0.8, value: 0.8)
            pixels += [UInt8(red * 255), UInt8(green * 255), UInt8(blue * 255), 255]
        }
        return try XCTUnwrap(CIImage(
            bitmapData: Data(pixels),
            bytesPerRow: hues.count * 4,
            size: CGSize(width: hues.count, height: 1),
            format: .RGBA8,
            colorSpace: space
        ))
    }

    private func rgb(hue: CGFloat, saturation: CGFloat, value: CGFloat)
        -> (CGFloat, CGFloat, CGFloat) {
        let h = hue / 60
        let chroma = value * saturation
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch h {
        case 0..<1: (r, g, b) = (chroma, x, 0)
        case 1..<2: (r, g, b) = (x, chroma, 0)
        case 2..<3: (r, g, b) = (0, chroma, x)
        case 3..<4: (r, g, b) = (0, x, chroma)
        case 4..<5: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        let match = value - chroma
        return (r + match, g + match, b + match)
    }

    private func pixel(_ bytes: [UInt8], _ index: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let offset = index * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]),
                Int(bytes[offset + 2]), Int(bytes[offset + 3]))
    }

    private func chroma(_ pixel: (r: Int, g: Int, b: Int, a: Int)) -> Int {
        max(pixel.r, pixel.g, pixel.b) - min(pixel.r, pixel.g, pixel.b)
    }

    func testModelHasEightFixedChannelsAndPhotographerRanges() throws {
        let mixer = ColorMixerAdjustments(
            red: ColorMixerChannel(hue: 20, saturation: -30, luminance: 40),
            orange: ColorMixerChannel(hue: -10),
            yellow: ColorMixerChannel(saturation: 25),
            green: ColorMixerChannel(luminance: -25),
            aqua: ColorMixerChannel(hue: 15),
            blue: ColorMixerChannel(saturation: 35),
            purple: ColorMixerChannel(luminance: 10),
            magenta: ColorMixerChannel(hue: -20)
        )

        XCTAssertEqual(mixer.channels.count, 8)
        XCTAssertFalse(mixer.isIdentity)
        XCTAssertEqual(ColorMixerChannel.hueRange, -100...100)
        XCTAssertEqual(ColorMixerChannel.saturationRange, -100...100)
        XCTAssertEqual(ColorMixerChannel.luminanceRange, -100...100)

        var clamped = ColorMixerChannel(hue: .infinity, saturation: -.infinity, luminance: .nan)
        XCTAssertEqual(clamped, .neutral)
        clamped.hue = 200
        clamped.saturation = -200
        clamped.luminance = 50
        XCTAssertEqual(clamped, ColorMixerChannel(hue: 100, saturation: -100, luminance: 50))
    }

    func testMixerStateRoundTripsAndMissingMixerMigratesToNeutral() throws {
        let mixer = ColorMixerAdjustments(
            red: ColorMixerChannel(hue: 12, saturation: -40, luminance: 8),
            magenta: ColorMixerChannel(hue: -18, saturation: 22, luminance: -11)
        )
        let document = EditDocument(color: ColorAdjustments(mixer: mixer))
        let decoded = try JSONDecoder().decode(
            EditDocument.self, from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(decoded, document)
        XCTAssertNotEqual(document.editHash, EditDocument().editHash)

        let oldColor = try JSONDecoder().decode(ColorAdjustments.self, from: Data("{}".utf8))
        XCTAssertEqual(oldColor.mixer, .neutral)
        XCTAssertTrue(oldColor.isIdentity)
    }

    func testMixerStateIsIncludedInUndoSnapshots() {
        let original = EditDocument()
        let edited = EditDocument(color: ColorAdjustments(
            mixer: ColorMixerAdjustments(green: ColorMixerChannel(luminance: 35))
        ))
        var history = EditHistory()
        history.recordChange(from: original, to: edited)

        XCTAssertEqual(history.undo(current: edited), original)
    }

    func testNeutralMixerIsExactIdentityAndPreservesAlpha() throws {
        let source = CIImage(color: CIColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let original = try Pixels.bytes(of: source)
        let rendered = try Pixels.bytes(of: RenderPipeline.applyColorMixer(.neutral, to: source))

        assertPixelsEqual(rendered, original, "neutral mixer must be an exact no-op")
        XCTAssertEqual(rendered[3], original[3])
    }

    func testMixerKeepsPremultipliedColorCorrectForTransparentPixels() throws {
        let source = CIImage(color: CIColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let mixer = ColorMixerAdjustments(red: ColorMixerChannel(saturation: -70))
        let rendered = try Pixels.bytes(of: RenderPipeline.applyColorMixer(mixer, to: source))

        XCTAssertEqual(rendered[3], 102, accuracy: 1)
        XCTAssertGreaterThan(abs(Int(rendered[0]) - Int(rendered[1])), 10,
                             "the visible colour should be adjusted before premultiplication")
    }

    func testEachChannelPrimarilyAffectsItsHueNeighborhood() throws {
        let source = try image(hues: hues)
        let base = try Pixels.bytes(of: source)
        let channelAdjustments: [ColorMixerChannel] = [
            ColorMixerChannel(saturation: 60), ColorMixerChannel(saturation: 60),
            ColorMixerChannel(saturation: 60), ColorMixerChannel(saturation: 60),
            ColorMixerChannel(saturation: 60), ColorMixerChannel(saturation: 60),
            ColorMixerChannel(saturation: 60), ColorMixerChannel(saturation: 60),
        ]

        for (channelIndex, adjustment) in channelAdjustments.enumerated() {
            var channels = [ColorMixerChannel](repeating: .neutral, count: 8)
            channels[channelIndex] = adjustment
            let mixer = ColorMixerAdjustments(
                red: channels[0], orange: channels[1], yellow: channels[2], green: channels[3],
                aqua: channels[4], blue: channels[5], purple: channels[6], magenta: channels[7]
            )
            let edited = try Pixels.bytes(of: RenderPipeline.applyColorMixer(mixer, to: source))
            let intendedDelta = chroma(pixel(edited, channelIndex)) - chroma(pixel(base, channelIndex))
            let remoteIndex = (channelIndex + 4) % 8
            let remoteDelta = abs(chroma(pixel(edited, remoteIndex)) - chroma(pixel(base, remoteIndex)))
            XCTAssertGreaterThan(intendedDelta, 4, "channel (channelIndex) should affect its hue")
            XCTAssertGreaterThanOrEqual(intendedDelta, remoteDelta,
                                        "channel (channelIndex) should be local")
        }
    }

    func testRedWraparoundIsContinuousAndOverlapIsSmooth() throws {
        let source = try image(hues: [359, 1, 28, 32])
        let mixer = ColorMixerAdjustments(red: ColorMixerChannel(saturation: -70))
        let base = try Pixels.bytes(of: source)
        let edited = try Pixels.bytes(of: RenderPipeline.applyColorMixer(mixer, to: source))

        XCTAssertLessThanOrEqual(
            abs(chroma(pixel(edited, 0)) - chroma(pixel(edited, 1))), 3,
            "red's hue window must wrap continuously at zero"
        )
        let left = abs(chroma(pixel(edited, 2)) - chroma(pixel(base, 2)))
        let right = abs(chroma(pixel(edited, 3)) - chroma(pixel(base, 3)))
        XCTAssertLessThan(abs(left - right), 20,
                          "adjacent hues should transition through a smooth overlap")
    }

    func testMixerChangesReachSharedGraphAndAreDeterministic() throws {
        let source = try image(hues: [0, 60, 180, 240])
        let document = EditDocument(color: ColorAdjustments(
            mixer: ColorMixerAdjustments(blue: ColorMixerChannel(hue: 35, luminance: 30))
        ))
        let first = try Pixels.bytes(of: RenderPipeline.buildImage(
            developed: source, document: document, lut: nil
        ))
        let second = try Pixels.bytes(of: RenderPipeline.buildImage(
            developed: source, document: document, lut: nil
        ))
        let neutral = try Pixels.bytes(of: RenderPipeline.buildImage(
            developed: source, document: EditDocument(), lut: nil
        ))

        assertPixelsEqual(first, second, "the mixer must be deterministic")
        assertPixelsDiffer(first, neutral, "mixer state must reach the shared render graph")
    }
}
