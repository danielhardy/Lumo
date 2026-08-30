import XCTest
import CoreImage
import CoreGraphics
@testable import LumoKit

/// The histogram moved in Step 6.
///
/// It used to be `ImageProcessor.histogram(of:)`, fed by `AppViewModel.processedImage` — a
/// full-resolution neutral decode with only the LUT on it. Deleting `processedImage` forced the
/// question, and the answer was to render it through the engine like everything else, so the panel
/// describes the pixels on screen rather than a differently-graded copy of them.
///
/// That split the work in two, and the tests follow the split: the **tally** is pure arithmetic over
/// a byte buffer and is checked against a buffer built by hand; the **render** belongs to the engine
/// and is checked there.
final class HistogramTests: TempDirectoryTestCase {

    // MARK: - The tally, against a hand-built buffer

    /// Pure red, 32×16. Every pixel counted once per channel, and the Rec.709 luma of pure red
    /// (0.2126) landing in bin 54.
    ///
    /// Built here rather than rendered: a decoder can only be asked for approximately the pixels you
    /// wanted, so an assertion on exact bin *indices* was always partly measuring Core Image. This
    /// measures the arithmetic.
    func testTallyCountsEveryPixelAndComputesRec709Luma() throws {
        let width = 32, height = 16
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = 255       // R
            bytes[i + 3] = 255   // A
        }

        let histogram = try XCTUnwrap(HistogramData(rgba8: bytes, width: width, height: height))

        XCTAssertEqual(histogram.binCount, 256)
        XCTAssertEqual(histogram.red.reduce(0, +), width * height)
        XCTAssertEqual(histogram.green.reduce(0, +), width * height)

        XCTAssertEqual(histogram.red[255], width * height)
        XCTAssertEqual(histogram.green[0], width * height)
        XCTAssertEqual(histogram.blue[0], width * height)

        // Rec.709 luma of pure red is 0.2126 → bin 54.
        XCTAssertEqual(histogram.luma.firstIndex { $0 > 0 }, 54)
        XCTAssertEqual(histogram.luma[54], width * height)
    }

    /// Rows can be padded, and reading past the end of a row would silently tally the wrong bytes.
    /// Two distinct rows plus padding bytes that must never be counted.
    func testTallyHonorsBytesPerRow() throws {
        let width = 2, height = 2, bytesPerRow = 16  // 8 bytes of pixels + 8 of padding
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        // Row 0: two mid-grey pixels. Row 1: two white pixels. Padding: 0x77, which is neither.
        for x in 0..<width {
            bytes[x * 4] = 128; bytes[x * 4 + 1] = 128; bytes[x * 4 + 2] = 128
            let row1 = bytesPerRow + x * 4
            bytes[row1] = 255; bytes[row1 + 1] = 255; bytes[row1 + 2] = 255
        }
        for row in 0..<height {
            for pad in (width * 4)..<bytesPerRow { bytes[row * bytesPerRow + pad] = 0x77 }
        }

        let histogram = try XCTUnwrap(
            HistogramData(rgba8: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
        )
        XCTAssertEqual(histogram.red[128], 2)
        XCTAssertEqual(histogram.red[255], 2)
        XCTAssertEqual(histogram.red[0x77], 0, "padding bytes must not be tallied")
        XCTAssertEqual(histogram.red.reduce(0, +), 4)
    }

    func testTallyRejectsABufferTooSmallForItsGeometry() {
        let bytes = [UInt8](repeating: 0, count: 4 * 4)  // enough for 4 pixels
        XCTAssertNil(HistogramData(rgba8: bytes, width: 4, height: 4),
                     "16 bytes cannot hold a 4×4 RGBA8 image")
        XCTAssertNil(HistogramData(rgba8: bytes, width: 0, height: 4))
        XCTAssertNil(HistogramData(rgba8: bytes, width: 2, height: 2, bytesPerRow: 4),
                     "a row stride narrower than the row itself is not a valid buffer")
    }

    func testNormalizationIgnoresClippingSpikes() {
        // One enormous spike at pure black must not flatten the interior.
        var red = [Int](repeating: 10, count: 256)
        red[0] = 1_000_000
        let data = HistogramData(red: red, green: red, blue: red, luma: red)
        let normalized = data.normalized(.red)
        XCTAssertEqual(normalized[1], 1.0, accuracy: 0.001,
                       "interior bins should scale to the interior max, not the clipping spike")
        XCTAssertEqual(normalized[0], 1.0, "the spike itself clamps to full height")
    }

    // MARK: - The render, through the engine

    private func makeSource(width: Int, height: Int, named name: String) throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(width: width, height: height, named: name, in: tempDirectory)
        return ImageSource(url: url, nativeExtent: CGSize(width: width, height: height))
    }

    /// `XCTUnwrap` takes an autoclosure, which cannot contain `await` — so the actor hop happens here
    /// and the unwrap happens after it. Same shape as `RenderEngineTests.render`.
    private func tally(
        _ engine: RenderEngine,
        _ source: ImageSource,
        _ document: EditDocument,
        lut: CubeLUT? = nil,
        space: WorkingSpace = .current,
        maxDimension: Int = 64
    ) async throws -> HistogramData {
        let result = await engine.histogram(
            source: source, document: document, lut: lut, scale: .full,
            space: space, maxDimension: maxDimension
        )
        return try XCTUnwrap(result)
    }

    /// `maxDimension` caps the tally buffer, so a big image does not mean a big allocation.
    func testTheEngineTalliesADownscaledRender() async throws {
        let engine = RenderEngine()
        let source = try makeSource(width: 900, height: 600, named: "big.png")

        let histogram = try await tally(engine, source, EditDocument())
        let total = histogram.red.reduce(0, +)
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThanOrEqual(total, 64 * 64, "the tally should cap at maxDimension²")
        XCTAssertLessThan(total, 900 * 600, "a 900×600 source must not be tallied at full size")
    }

    /// The document reaches the tally. An adjustment that visibly moves the tone must move the
    /// histogram — this is the whole reason the histogram was cut over rather than left reading a
    /// LUT-only image.
    func testTheDocumentReachesTheHistogram() async throws {
        let engine = RenderEngine()
        let source = try makeSource(width: 96, height: 64, named: "src.png")

        let warm = TestImages.warmLUT()
        let neutral = try await tally(engine, source, EditDocument())
        let brightened = try await tally(
            engine, source, EditDocument(adjustments: [.exposure(ev: 1.5)])
        )
        let graded = try await tally(
            engine, source, EditDocument(lut: LUTSettings(lutID: warm.lutID, intensity: 1)), lut: warm
        )

        XCTAssertEqual(neutral.red.reduce(0, +), brightened.red.reduce(0, +),
                       "both should still tally every pixel")
        XCTAssertNotEqual(neutral.red, brightened.red, "an adjustment must move the histogram")
        XCTAssertNotEqual(neutral.red, graded.red, "the LUT must move the histogram")
        XCTAssertNotEqual(brightened.red, graded.red,
                          "…and the two must not be collapsing to the same render")
    }

    /// The histogram is rendered in the working space, like the preview raster it describes. A fixed
    /// sRGB tally would be identical in both.
    func testTheHistogramFollowsTheWorkingSpace() async throws {
        let engine = RenderEngine()
        let source = try makeSource(width: 64, height: 64, named: "space.png")

        let inSRGB = try await tally(engine, source, EditDocument(), space: .sRGB)
        let inP3 = try await tally(engine, source, EditDocument(), space: .displayP3)

        XCTAssertEqual(inSRGB.red.reduce(0, +), inP3.red.reduce(0, +), "both should tally every pixel")
        XCTAssertNotEqual(inSRGB.red, inP3.red, "the histogram should follow the render space")
    }

    func testAnUndecodableSourceHasNoHistogram() async {
        let engine = RenderEngine()
        let junk = ImageSource(backing: .data(Data("not an image".utf8)), kind: .standard, nativeExtent: .zero)
        let histogram = await engine.histogram(
            source: junk, document: EditDocument(), lut: nil, scale: .full,
            space: .current, maxDimension: 64
        )
        XCTAssertNil(histogram)
    }
}
