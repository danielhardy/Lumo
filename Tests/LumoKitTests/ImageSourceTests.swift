import XCTest
import CoreGraphics
import CoreImage
@testable import LumoKit

/// The two Step 2 types that describe the *input* to a render rather than the edit: what the source
/// is, and how big to render it.
final class ImageSourceTests: TempDirectoryTestCase {

    // MARK: - Classification

    func testFileSourcesAreClassifiedByExtensionLikeTheLoader() {
        for ext in ImageDecoder.rawExtensions {
            let url = URL(fileURLWithPath: "/photos/frame.\(ext)")
            XCTAssertEqual(ImageSource(url: url, nativeExtent: .zero).kind, .raw, ext)
        }
        for ext in ["jpg", "JPEG", "png", "tiff", "heic"] {
            let url = URL(fileURLWithPath: "/photos/frame.\(ext)")
            XCTAssertEqual(ImageSource(url: url, nativeExtent: .zero).kind, .standard, ext)
        }
        // Case-insensitive, because cameras write .DNG and .NEF in caps.
        XCTAssertEqual(ImageSource(url: URL(fileURLWithPath: "/a/B.DNG"), nativeExtent: .zero).kind, .raw)
    }

    /// A Photos import arrives as bytes with **no URL at all**, so there is no extension to read.
    /// This is why `Backing` has a `.data` case rather than the import being temp-filed: a temp file
    /// would need an invented filename, and extension-based detection would then classify the file by
    /// whatever was guessed.
    func testDataSourcesAreClassifiedByContent() throws {
        let url = try Fixtures.writeJPEG(width: 16, height: 12, orientation: 1,
                                         named: "photo.jpg", in: tempDirectory)
        let jpegData = try Data(contentsOf: url)

        let source = ImageSource(data: jpegData, nativeExtent: CGSize(width: 16, height: 12))
        XCTAssertEqual(source.kind, .standard)
        XCTAssertEqual(source.backing, .data(jpegData))

        // Undecodable bytes fall back to the standard path, which fails with a legible
        // "cannot load" rather than a RAW decoder failing obscurely.
        XCTAssertEqual(ImageSource.kind(forData: Data("not an image".utf8)), .standard)
        XCTAssertEqual(ImageSource.kind(forData: Data()), .standard)
    }

    /// The half the extension rule cannot cover: RAW bytes with no filename. A local file may still
    /// be usable through its URL extension while the current decoder refuses its extension-free
    /// byte payload, so only decoder-recognized byte fixtures participate in this check.
    func testRAWBytesAreDetectedWithoutAFilename() throws {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else {
            throw XCTSkip("no local RAW to classify; see Fixtures.localRAWURL")
        }

        var recognizedByteFixtures = 0
        for url in urls {
            let rawData = try Data(contentsOf: url)
            guard CIRAWFilter(imageData: rawData, identifierHint: nil) != nil else {
                print("Skipping \(url.lastPathComponent): current decoder does not recognize RAW bytes")
                continue
            }
            recognizedByteFixtures += 1
            XCTAssertEqual(ImageSource.kind(forData: rawData), .raw,
                           "a RAW delivered as bytes must still take the RAW path")
            XCTAssertEqual(ImageSource(data: rawData, nativeExtent: .zero).kind, .raw)
        }

        guard recognizedByteFixtures > 0 else {
            throw XCTSkip("current decoder does not recognize any local RAW as extension-free bytes")
        }
    }

    func testSourcesAreEqualOnlyWhenTheirBytesAndKindMatch() throws {
        let a = ImageSource(url: URL(fileURLWithPath: "/a.dng"), nativeExtent: CGSize(width: 100, height: 50))
        let same = ImageSource(url: URL(fileURLWithPath: "/a.dng"), nativeExtent: CGSize(width: 100, height: 50))
        let otherFile = ImageSource(url: URL(fileURLWithPath: "/b.dng"), nativeExtent: CGSize(width: 100, height: 50))
        let otherExtent = ImageSource(url: URL(fileURLWithPath: "/a.dng"), nativeExtent: CGSize(width: 50, height: 100))

        XCTAssertEqual(a, same)
        XCTAssertNotEqual(a, otherFile)
        XCTAssertNotEqual(a, otherExtent)

        // A URL-backed and a data-backed source are never equal, even for the same image.
        let bytes = ImageSource(backing: .data(Data([1, 2, 3])), kind: .raw,
                                nativeExtent: CGSize(width: 100, height: 50))
        XCTAssertNotEqual(a, bytes)
    }

    // MARK: - RenderScale

    func testFullScaleIsAlwaysOne() {
        XCTAssertEqual(RenderScale.full.factor(for: CGSize(width: 6000, height: 4000)), 1.0)
        XCTAssertEqual(RenderScale.full.factor(for: CGSize(width: 1, height: 1)), 1.0)
    }

    func testPreviewFitsInsideTheBoxOnTheLimitingAxis() {
        let landscape = CGSize(width: 6000, height: 4000)
        let scale = RenderScale.preview(maxSize: CGSize(width: 1600, height: 1200))
            .factor(for: landscape)

        // Width is the tighter constraint: 1600/6000 < 1200/4000.
        XCTAssertEqual(scale, 1600.0 / 6000.0, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(landscape.width * scale, 1600)
        XCTAssertLessThanOrEqual(landscape.height * scale, 1200)

        // And the other way round for a portrait image, where height binds.
        let portrait = CGSize(width: 4000, height: 6000)
        let portraitScale = RenderScale.preview(maxSize: CGSize(width: 1600, height: 1200))
            .factor(for: portrait)
        XCTAssertEqual(portraitScale, 1200.0 / 6000.0, accuracy: 1e-12)
    }

    /// A preview box bigger than the image renders at 1.0. Magnifying to fill the box would cost
    /// pixels for no detail and would put an upscaled image through the LUT.
    func testPreviewNeverUpscales() {
        let scale = RenderScale.preview(maxSize: CGSize(width: 4000, height: 4000))
            .factor(for: CGSize(width: 200, height: 100))
        XCTAssertEqual(scale, 1.0)
    }

    func testInteractiveScaleUsesDrawableSizeAndPixelBudget() {
        let drawable = CGSize(width: 2400, height: 1600)
        let scale = RenderScale.interactive(maxSize: drawable)
        let target = try! XCTUnwrap(scale.targetSize)

        XCTAssertNotEqual(scale, .preview(maxSize: drawable))
        XCTAssertLessThanOrEqual(target.width * target.height, 1_500_001)
        XCTAssertLessThanOrEqual(target.width, drawable.width)
        XCTAssertLessThanOrEqual(target.height, drawable.height)
    }

    func testInteractiveFactorUsesItsPixelBudgetForA60MPSource() {
        let source = CGSize(width: 9_504, height: 6_336)
        let scale = RenderScale.interactive(maxSize: CGSize(width: 2_400, height: 1_600))
        let factor = scale.factor(for: source)
        let renderedPixels = source.width * factor * source.height * factor

        XCTAssertLessThanOrEqual(renderedPixels, 1_500_001,
                                 "interactive RAW development must honor its pixel budget")
        XCTAssertLessThan(factor, 2_400 / source.width,
                          "the interactive tier must be smaller than the full drawable when capped")
    }

    /// Degenerate inputs return 1.0 rather than 0 or NaN. A zero scale reaches `Int(width)` as a
    /// zero-sized raster; a NaN one traps there. Both are the caller's extent check to reject, not
    /// this function's to produce.
    func testDegenerateExtentsFallBackToOne() {
        let box = RenderScale.preview(maxSize: CGSize(width: 1600, height: 1200))
        XCTAssertEqual(box.factor(for: .zero), 1.0)
        XCTAssertEqual(box.factor(for: CGSize(width: 100, height: 0)), 1.0)
        XCTAssertEqual(box.factor(for: CGSize(width: -100, height: -100)), 1.0)
        XCTAssertEqual(box.factor(for: CGSize(width: CGFloat.infinity, height: 100)), 1.0)
        XCTAssertEqual(box.factor(for: CGSize(width: CGFloat.nan, height: 100)), 1.0)

        let emptyBox = RenderScale.preview(maxSize: .zero)
        XCTAssertEqual(emptyBox.factor(for: CGSize(width: 6000, height: 4000)), 1.0)
    }

    func testPreviewBoxIsPartOfTheScaleIdentity() {
        XCTAssertEqual(RenderScale.preview(maxSize: CGSize(width: 100, height: 100)),
                       .preview(maxSize: CGSize(width: 100, height: 100)))
        XCTAssertNotEqual(RenderScale.preview(maxSize: CGSize(width: 100, height: 100)),
                          .preview(maxSize: CGSize(width: 200, height: 200)))
        XCTAssertNotEqual(RenderScale.preview(maxSize: CGSize(width: 100, height: 100)), .full)
    }
}
