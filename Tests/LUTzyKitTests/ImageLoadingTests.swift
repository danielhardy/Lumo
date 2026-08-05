import XCTest
import CoreImage
import ImageIO
@testable import LUTzyKit

/// Regression coverage for B1 — EXIF orientation being ignored on every non-RAW
/// load, so a portrait photo previewed and exported on its side while its own
/// filmstrip thumbnail stood upright.
///
/// The trap is that `CIImage(contentsOf:)` does not honor the orientation tag
/// but `CIRAWFilter` and `CGImageSourceCreateThumbnailAtIndex(…WithTransform)`
/// both do — so the bug only shows when two paths are compared, which is
/// exactly what these tests do.
final class ImageLoadingTests: TempDirectoryTestCase {

    /// Every quarter-turn orientation, and one that isn't.
    private let quarterTurns = [5, 6, 7, 8]
    private let upright = 1

    func testLoadFromURLAppliesOrientation() throws {
        // A landscape 80×60 buffer tagged "rotate to portrait".
        for orientation in quarterTurns {
            let url = try Fixtures.writeJPEG(
                width: 80, height: 60, orientation: orientation,
                named: "portrait-\(orientation).jpg", in: tempDirectory
            )
            XCTAssertEqual(Fixtures.storedSize(of: url), CGSize(width: 80, height: 60),
                           "fixture should keep a landscape pixel buffer")

            let image = try ImageProcessor.shared.loadImage(from: url)
            XCTAssertEqual(image.extent.width, 60,
                           "orientation \(orientation) should display 60 wide")
            XCTAssertEqual(image.extent.height, 80,
                           "orientation \(orientation) should display 80 tall")
        }
    }

    func testLoadFromURLLeavesUprightImagesAlone() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: upright,
            named: "landscape.jpg", in: tempDirectory
        )
        let image = try ImageProcessor.shared.loadImage(from: url)
        XCTAssertEqual(image.extent.width, 80)
        XCTAssertEqual(image.extent.height, 60)
    }

    /// The Photos-import path decodes from `Data`, not a URL, and had the same
    /// defect independently.
    func testLoadFromDataAppliesOrientation() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "fromdata.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let image = try ImageProcessor.shared.loadImage(from: data, name: "fromdata.jpg")
        XCTAssertEqual(image.extent.width, 60)
        XCTAssertEqual(image.extent.height, 80)
    }

    func testLoadFromDataThrowsOnGarbage() {
        let garbage = Data("not an image".utf8)
        XCTAssertThrowsError(try ImageProcessor.shared.loadImage(from: garbage, name: "bad.txt"))
    }

    func testLoadFromURLThrowsOnMissingFile() {
        let missing = tempDirectory.appendingPathComponent("nope.jpg")
        XCTAssertThrowsError(try ImageProcessor.shared.loadImage(from: missing))
    }

    /// The heart of the bug: preview and thumbnail disagreed. They must agree
    /// on which way is up, or the filmstrip contradicts the canvas.
    func testPreviewAndThumbnailAgreeOnOrientation() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "agree.jpg", in: tempDirectory
        )
        let loaded = try ImageProcessor.shared.loadImage(from: url)
        let thumbnail = try XCTUnwrap(ImageProcessor.shared.generateThumbnail(from: url))

        let loadedIsPortrait = loaded.extent.height > loaded.extent.width
        let thumbIsPortrait = thumbnail.size.height > thumbnail.size.width
        XCTAssertEqual(loadedIsPortrait, thumbIsPortrait,
                       "canvas and filmstrip must not disagree about orientation")
        XCTAssertTrue(loadedIsPortrait, "both should be portrait for orientation 6")
    }

    /// Exports were written sideways too, which is the part a user can't undo.
    func testExportPreservesDisplayOrientation() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "toexport.jpg", in: tempDirectory
        )
        let loaded = try ImageProcessor.shared.loadImage(from: url)

        for format in ImageProcessor.ExportFormat.allCases {
            let out = tempDirectory.appendingPathComponent("out.\(format.fileExtension)")
            try ImageProcessor.shared.export(loaded, to: out, format: format)
            XCTAssertEqual(Fixtures.storedSize(of: out), CGSize(width: 60, height: 80),
                           "\(format.rawValue) export should be written upright")
        }
    }

    func testMetadataReportsDisplayDimensions() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "meta.jpg", in: tempDirectory
        )
        let metadata = ImageMetadata.read(from: url)
        XCTAssertEqual(metadata.pixelWidth, 60, "inspector should report what's on screen")
        XCTAssertEqual(metadata.pixelHeight, 80)
    }

    func testMetadataFromDataMatchesMetadataFromURL() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "both.jpg", in: tempDirectory
        )
        let fromURL = ImageMetadata.read(from: url)
        let fromData = ImageMetadata.read(from: try Data(contentsOf: url))
        XCTAssertEqual(fromURL.pixelWidth, fromData.pixelWidth)
        XCTAssertEqual(fromURL.pixelHeight, fromData.pixelHeight)
    }

    // MARK: - Format routing

    /// `supportedExtensions` is the single source of truth shared by the open
    /// panel and the folder scanner; RAW and standard sets must stay disjoint
    /// or `loadImage` would route a file down the wrong decoder.
    func testSupportedExtensionsCoverRAWAndStandard() {
        XCTAssertTrue(ImageProcessor.supportedExtensions.contains("dng"))
        XCTAssertTrue(ImageProcessor.supportedExtensions.contains("jpg"))
        XCTAssertTrue(ImageProcessor.supportedExtensions.contains("heic"))
        XCTAssertFalse(ImageProcessor.supportedExtensions.contains("cube"))
        XCTAssertFalse(ImageProcessor.supportedExtensions.contains("pdf"))

        XCTAssertTrue(ImageProcessor.rawExtensions.isSubset(of: ImageProcessor.supportedExtensions))
        XCTAssertFalse(ImageProcessor.rawExtensions.contains("jpg"),
                       "a RAW/standard overlap would send JPEGs through CIRAWFilter")
        XCTAssertTrue(ImageProcessor.supportedExtensions.allSatisfy { $0 == $0.lowercased() },
                      "extensions are matched lowercased at the call sites")
    }

    func testSupportedTypesIncludeRawAndAreUnique() {
        let identifiers = ImageProcessor.supportedTypes.map(\.identifier)
        XCTAssertTrue(identifiers.contains("public.camera-raw-image"))
        XCTAssertEqual(identifiers.count, Set(identifiers).count, "open panel types should not repeat")
    }

    // MARK: - Preview rendering

    func testRenderPreviewCapsSizeAndPreservesAspect() throws {
        let url = try Fixtures.writeJPEG(
            width: 800, height: 600, orientation: upright, named: "big.jpg", in: tempDirectory
        )
        let image = try ImageProcessor.shared.loadImage(from: url)
        let preview = try XCTUnwrap(ImageProcessor.shared.renderPreview(
            image, maxSize: CGSize(width: 200, height: 200)
        ))
        XCTAssertLessThanOrEqual(preview.size.width, 200)
        XCTAssertLessThanOrEqual(preview.size.height, 200)
        XCTAssertEqual(preview.size.width / preview.size.height, 800.0 / 600.0, accuracy: 0.02)
    }

    func testRenderPreviewDoesNotUpscale() throws {
        let url = try Fixtures.writeJPEG(
            width: 40, height: 30, orientation: upright, named: "small.jpg", in: tempDirectory
        )
        let image = try ImageProcessor.shared.loadImage(from: url)
        let preview = try XCTUnwrap(ImageProcessor.shared.renderPreview(
            image, maxSize: CGSize(width: 1600, height: 1200)
        ))
        XCTAssertEqual(preview.size.width, 40)
        XCTAssertEqual(preview.size.height, 30)
    }

    // MARK: - Histogram

    func testHistogramTalliesEveryPixel() throws {
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 16))
        let histogram = try XCTUnwrap(ImageProcessor.shared.histogram(of: image, maxDimension: 64))

        XCTAssertEqual(histogram.binCount, 256)
        XCTAssertEqual(histogram.red.reduce(0, +), 32 * 16)
        XCTAssertEqual(histogram.green.reduce(0, +), 32 * 16)

        // Pure red: red maxed, green and blue at zero.
        XCTAssertEqual(histogram.red[255], 32 * 16)
        XCTAssertEqual(histogram.green[0], 32 * 16)
        XCTAssertEqual(histogram.blue[0], 32 * 16)

        // Rec.709 luma of pure red is 0.2126 → bin 54.
        XCTAssertEqual(histogram.luma.firstIndex { $0 > 0 }, 54)
    }

    func testHistogramDownscalesLargeImages() throws {
        let image = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 3000))
        let histogram = try XCTUnwrap(ImageProcessor.shared.histogram(of: image, maxDimension: 64))
        let total = histogram.red.reduce(0, +)
        XCTAssertLessThan(total, 4000 * 3000, "histogram should tally a downscaled render")
        XCTAssertGreaterThan(total, 0)
    }

    func testHistogramRejectsInfiniteExtent() {
        // A bare CIImage(color:) has an infinite extent; tallying it would try
        // to allocate an unbounded buffer.
        XCTAssertNil(ImageProcessor.shared.histogram(of: CIImage(color: .gray)))
    }

    func testHistogramNormalizationIgnoresClippingSpikes() {
        // One enormous spike at pure black must not flatten the interior.
        var red = [Int](repeating: 10, count: 256)
        red[0] = 1_000_000
        let data = HistogramData(red: red, green: red, blue: red, luma: red)
        let normalized = data.normalized(.red)
        XCTAssertEqual(normalized[1], 1.0, accuracy: 0.001,
                       "interior bins should scale to the interior max, not the clipping spike")
        XCTAssertEqual(normalized[0], 1.0, "the spike itself clamps to full height")
    }
}
