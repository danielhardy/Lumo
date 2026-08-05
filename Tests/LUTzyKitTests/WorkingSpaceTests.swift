import XCTest
import CoreImage
import CoreGraphics
import AppKit
import simd
@testable import LUTzyKit

/// Phase 2 Step 1. Two things are being pinned down here:
///
/// 1. **Preview and export rasterize through the same colour space.** They did not: `createCGImage`
///    was called with no space at all, so the preview used the `CIContext` default while export
///    forced sRGB. Byte-identical while everything was sRGB, silently divergent otherwise.
/// 2. **LUT interpolation and output encoding move in lockstep.** They were independent literals
///    that merely happened to agree. A test that only checks today's sRGB values would pass either
///    way, so the lockstep tests drive a *non-default* space through both halves.
final class WorkingSpaceTests: TempDirectoryTestCase {

    // MARK: - The seam itself

    func testCurrentIsSRGB() {
        XCTAssertEqual(WorkingSpace.current, .sRGB)
        XCTAssertEqual(WorkingSpace.sRGB.cgColorSpace.name, CGColorSpace.sRGB)
        XCTAssertEqual(WorkingSpace.displayP3.cgColorSpace.name, CGColorSpace.displayP3)
    }

    func testEveryCaseResolvesToARealColorSpace() {
        // The accessor force-unwraps; this is what makes that safe.
        for space in WorkingSpace.allCases {
            XCTAssertNotNil(space.cgColorSpace.name, "\(space) should resolve to a system colour space")
        }
    }

    // MARK: - Preview / export parity

    /// The ship gate for Step 1: the preview raster and the exported file must be the same pixels.
    func testPreviewRasterMatchesExportedBytes() throws {
        let source = try gradientImage(width: 64, height: 48)
        let processor = ImageProcessor.shared

        // Preview at a size that forces no downscale, so any difference is colour, not resampling.
        let preview = try XCTUnwrap(processor.renderPreview(
            source, maxSize: CGSize(width: 4096, height: 4096)
        ))
        let previewPixels = try pixels(of: try XCTUnwrap(cgImage(from: preview)))

        // Export through the lossless encoder and read it back.
        let exported = tempDirectory.appendingPathComponent("parity.png")
        try processor.export(source, to: exported, format: .png)
        let exportedPixels = try pixels(of: try XCTUnwrap(cgImage(atPath: exported)))

        XCTAssertEqual(previewPixels.count, exportedPixels.count)
        assertPixelsEqual(previewPixels, exportedPixels, tolerance: 1,
                          "preview and export must rasterize through the same colour space")
    }

    /// Same, with a LUT in the chain — the case where interpolation space and encoding space could
    /// disagree with each other rather than just with the context default.
    func testPreviewMatchesExportWithALUTApplied() throws {
        let source = try gradientImage(width: 64, height: 48)
        let lut = try warmLUT()
        let graded = try XCTUnwrap(lut.apply(to: source, intensity: 1))
        let processor = ImageProcessor.shared

        let preview = try XCTUnwrap(processor.renderPreview(
            graded, maxSize: CGSize(width: 4096, height: 4096)
        ))
        let previewPixels = try pixels(of: try XCTUnwrap(cgImage(from: preview)))

        let exported = tempDirectory.appendingPathComponent("parity-lut.png")
        try processor.export(graded, to: exported, format: .png)
        let exportedPixels = try pixels(of: try XCTUnwrap(cgImage(atPath: exported)))

        assertPixelsEqual(previewPixels, exportedPixels, tolerance: 1,
                          "a graded preview must match a graded export")
    }

    // MARK: - Lockstep

    /// If the two halves of the seam were still independent, driving a non-default space through
    /// them would produce a mismatch. This is the test that would have caught the original defect.
    func testLUTInterpolationAndOutputMoveTogether() throws {
        let source = try gradientImage(width: 64, height: 48)
        let lut = try warmLUT()
        let processor = ImageProcessor.shared

        for space in WorkingSpace.allCases {
            let graded = try XCTUnwrap(lut.apply(to: source, intensity: 1, space: space))

            let preview = try XCTUnwrap(processor.renderPreview(
                graded, maxSize: CGSize(width: 4096, height: 4096), space: space
            ))
            let previewPixels = try pixels(of: try XCTUnwrap(cgImage(from: preview)))

            let exported = tempDirectory.appendingPathComponent("lockstep-\(space.rawValue).png")
            try processor.export(graded, to: exported, format: .png, space: space)
            let exportedPixels = try pixels(of: try XCTUnwrap(cgImage(atPath: exported)))

            assertPixelsEqual(previewPixels, exportedPixels, tolerance: 1,
                              "preview and export disagree in \(space.rawValue)")
        }
    }

    /// And the space has to actually reach the encoder — otherwise the lockstep test above would
    /// pass trivially by ignoring its argument in both places.
    func testWorkingSpaceReachesTheOutputEncoder() throws {
        let source = try gradientImage(width: 32, height: 32)
        let processor = ImageProcessor.shared

        let asSRGB = tempDirectory.appendingPathComponent("srgb.png")
        let asP3 = tempDirectory.appendingPathComponent("p3.png")
        try processor.export(source, to: asSRGB, format: .png, space: .sRGB)
        try processor.export(source, to: asP3, format: .png, space: .displayP3)

        let sRGBName = try XCTUnwrap(cgImage(atPath: asSRGB)).colorSpace?.name as String?
        let p3Name = try XCTUnwrap(cgImage(atPath: asP3)).colorSpace?.name as String?

        XCTAssertNotEqual(sRGBName, p3Name, "the exported files should carry different profiles")
        XCTAssertEqual(sRGBName, CGColorSpace.sRGB as String)
        XCTAssertEqual(p3Name, CGColorSpace.displayP3 as String)
    }

    func testWorkingSpaceReachesTheLUTInterpolation() throws {
        // A cube that isn't the identity will interpolate differently in a wider space, so the two
        // renders must differ. If makeFilter ignored its argument they would be identical.
        let source = try gradientImage(width: 32, height: 32)
        let lut = try warmLUT()

        let inSRGB = try XCTUnwrap(lut.apply(to: source, space: .sRGB))
        let inP3 = try XCTUnwrap(lut.apply(to: source, space: .displayP3))

        // Rasterize both through the SAME space so only the interpolation differs.
        let processor = ImageProcessor.shared
        let a = try pixels(of: try XCTUnwrap(cgImage(from: try XCTUnwrap(
            processor.renderPreview(inSRGB, maxSize: CGSize(width: 4096, height: 4096), space: .sRGB)))))
        let b = try pixels(of: try XCTUnwrap(cgImage(from: try XCTUnwrap(
            processor.renderPreview(inP3, maxSize: CGSize(width: 4096, height: 4096), space: .sRGB)))))

        XCTAssertNotEqual(a, b, "the cube's interpolation space should affect the result")
    }

    // MARK: - Derive stays pinned

    /// `RecipeExtractor` must fit in sRGB regardless of `WorkingSpace.current`, because the space a
    /// cube is fit in has to equal the space it is applied in. This asserts the contract that makes
    /// that reasoning valid today; if `.current` ever moves, this test is the tripwire.
    func testDeriveFitSpaceEqualsApplySpace() {
        XCTAssertEqual(
            WorkingSpace.current, .sRGB,
            """
            RecipeExtractor is pinned to .sRGB. If WorkingSpace.current has moved, derived LUTs are \
            now fit in a different space than they are applied in and will mis-map. Re-fit derive, \
            or stamp the build space onto CubeLUT — see WorkingSpace and PHASE2_SPEC §4.4.
            """
        )
    }

    // MARK: - Histogram follows the preview

    func testHistogramUsesTheSameSpaceAsThePreview() throws {
        // Same image, two spaces: the tallies should differ, proving the histogram describes the
        // pixels actually on screen rather than a fixed sRGB copy of them.
        let source = try gradientImage(width: 64, height: 64)
        let processor = ImageProcessor.shared

        let inSRGB = try XCTUnwrap(processor.histogram(of: source, maxDimension: 64, space: .sRGB))
        let inP3 = try XCTUnwrap(processor.histogram(of: source, maxDimension: 64, space: .displayP3))

        XCTAssertEqual(inSRGB.red.reduce(0, +), inP3.red.reduce(0, +), "both should tally every pixel")
        XCTAssertNotEqual(inSRGB.red, inP3.red, "the histogram should follow the render space")
    }

    // MARK: - Helpers

    /// A horizontal red→blue ramp: exercises the whole gamut rather than one flat colour, so a
    /// colour-space difference actually shows up.
    private func gradientImage(width: Int, height: Int) throws -> CIImage {
        let filter = try XCTUnwrap(CIFilter(name: "CILinearGradient"))
        filter.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        filter.setValue(CIVector(x: CGFloat(width), y: 0), forKey: "inputPoint1")
        filter.setValue(CIColor(red: 0.9, green: 0.1, blue: 0.1), forKey: "inputColor0")
        filter.setValue(CIColor(red: 0.1, green: 0.2, blue: 0.9), forKey: "inputColor1")
        let output = try XCTUnwrap(filter.outputImage)
        return output.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// A non-identity cube that warms the image, so interpolation space matters.
    private func warmLUT() throws -> CubeLUT {
        let size = 4
        var cube = [SIMD3<Float>]()
        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    cube.append(SIMD3(
                        min(1, Float(r) / denom * 1.2),
                        Float(g) / denom,
                        Float(b) / denom * 0.8
                    ))
                }
            }
        }
        return CubeLUT(cube: cube, size: size, name: "warm")
    }

    private func cgImage(from nsImage: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func cgImage(atPath url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Read a CGImage back as raw RGBA8 in its own colour space, so no conversion is introduced by
    /// the comparison itself.
    private func pixels(of image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    /// Compare with a small tolerance: both paths go through the GPU, and rounding at the 8-bit
    /// boundary can differ by a unit without meaning the spaces disagree.
    private func assertPixelsEqual(
        _ a: [UInt8], _ b: [UInt8], tolerance: Int, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard a.count == b.count else {
            return XCTFail("\(message) — byte counts differ (\(a.count) vs \(b.count))", file: file, line: line)
        }
        var worst = 0
        var worstIndex = -1
        for i in a.indices {
            let delta = abs(Int(a[i]) - Int(b[i]))
            if delta > worst { worst = delta; worstIndex = i }
        }
        XCTAssertLessThanOrEqual(
            worst, tolerance,
            "\(message) — worst delta \(worst) at byte \(worstIndex)", file: file, line: line
        )
    }
}
