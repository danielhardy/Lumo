import XCTest
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LumoKit

/// Thumbnails, and the two `ImageCollection` sites that produce them.
///
/// `docs/PHASE2_SPEC.md` §6 names both sites explicitly — `generateThumbnails` and `addFromData` —
/// because they are independent code paths that happen to want the same thing, and the second one is
/// easy to miss. Before Step 7 only the first had any coverage at all: `addFromData` built its
/// thumbnails inline and nothing tested it, so pointing one site at a new helper and forgetting the
/// other would have been a silent, green change.
@MainActor
final class ThumbnailTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - The helper

    func testGenerateCapsTheLongEdge() throws {
        let url = try Fixtures.writeJPEG(
            width: 800, height: 600, orientation: 1, named: "big.jpg", in: tempDirectory
        )
        let thumb = try XCTUnwrap(Thumbnails.generate(from: url, maxPixelSize: 64))

        XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height), 64)
        XCTAssertEqual(thumb.size.width / thumb.size.height, 800.0 / 600.0, accuracy: 0.05,
                       "the aspect ratio should survive")
        // A size other than the default on purpose: `defaultMaxPixelSize` would pass against a
        // helper that ignored its argument.
        XCTAssertNotEqual(max(thumb.size.width, thumb.size.height),
                          CGFloat(Thumbnails.defaultMaxPixelSize))
    }

    /// B1's regression, on the thumbnail side. A portrait JPEG must come back portrait, or the
    /// filmstrip contradicts the canvas — which is exactly what shipped before the orientation fix.
    func testGenerateBakesEXIFOrientation() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "portrait.jpg", in: tempDirectory
        )
        let thumb = try XCTUnwrap(Thumbnails.generate(from: url))
        XCTAssertGreaterThan(thumb.size.height, thumb.size.width,
                             "orientation 6 is portrait; the thumbnail must agree with the canvas")
    }

    /// The URL and Data entry points are separate `CGImageSource` constructors, and the app reaches
    /// each from a different `ImageCollection` site. They must not disagree.
    ///
    /// The fixture is deliberately **larger than the cap**. A first draft used an 80×60 image, which
    /// is under `defaultMaxPixelSize` and so came back at native size through both paths — the
    /// comparison held even against a data path that halved its `maxPixelSize`, because neither side
    /// was downscaling at all. A mutation caught that.
    func testTheDataAndURLEntryPointsAgree() throws {
        let url = try Fixtures.writeJPEG(
            width: 800, height: 600, orientation: 6, named: "both.jpg", in: tempDirectory
        )
        let fromURL = try XCTUnwrap(Thumbnails.generate(from: url))
        let fromData = try XCTUnwrap(Thumbnails.generate(from: try Data(contentsOf: url)))

        XCTAssertEqual(fromURL.size, fromData.size,
                       "a Photos import and a file import must produce the same thumbnail")
        XCTAssertEqual(max(fromURL.size.width, fromURL.size.height),
                       CGFloat(Thumbnails.defaultMaxPixelSize),
                       "the source is bigger than the cap, so both paths must actually downscale")
        XCTAssertGreaterThan(fromData.size.height, fromData.size.width,
                             "the data path must bake orientation too, not just the URL path")
    }

    /// B11's invariant, which had no test: a thumbnail must land on the row for **its own file**.
    ///
    /// A refresh can replace `items` while decodes are in flight, and the fix was to match on the
    /// item's `id` rather than trust the index. Today every site that replaces `items` cancels the
    /// thumbnail task first, so the id lookup is defence in depth and a mutation to index-matching
    /// is not observable — which is exactly why the *behaviour* is worth pinning rather than the
    /// implementation. Distinct solid colours make a mislabelled thumbnail visible.
    func testARefreshThatReordersNeverMislabelsAThumbnail() async throws {
        // "b" and "c" first; "a" arrives later and sorts ahead of both, shifting every index.
        try writeSolidPNG(named: "b.png", red: 0.9, green: 0.1, blue: 0.1)
        try writeSolidPNG(named: "c.png", red: 0.1, green: 0.9, blue: 0.1)

        let collection = ImageCollection()
        collection.loadFromFolder(tempDirectory)
        try await waitUntil("the first scan") { collection.items.count == 2 }

        try writeSolidPNG(named: "a.png", red: 0.1, green: 0.1, blue: 0.9)
        // `refresh()` reads `sourceFolderURL`, which only `setSourceFolder` sets — and that writes a
        // security-scoped bookmark into `UserDefaults`, which a test has no business doing. Calling
        // `loadFromFolder` again is the same rescan without the side effect.
        collection.loadFromFolder(tempDirectory)

        try await waitUntil("thumbnails after the reorder") {
            collection.items.count == 3 && collection.items.allSatisfy { $0.thumbnail != nil }
        }
        XCTAssertEqual(collection.items.map(\.displayName), ["a", "b", "c"],
                       "the rescan should have reordered")

        let expected: [String: (Int, Int, Int)] = [
            "a": (0, 0, 2), "b": (2, 0, 0), "c": (0, 2, 0),   // dominant channel per file
        ]
        for item in collection.items {
            let thumb = try XCTUnwrap(item.thumbnail)
            let (r, g, b) = try dominantChannel(of: thumb)
            let want = try XCTUnwrap(expected[item.displayName])
            XCTAssertEqual([r, g, b].firstIndex(of: [r, g, b].max()!),
                           [want.0, want.1, want.2].firstIndex(of: [want.0, want.1, want.2].max()!),
                           "\(item.displayName) is showing another file's thumbnail")
        }
    }

    func testGenerateReturnsNilForUndecodableInput() throws {
        let junk = tempDirectory.appendingPathComponent("junk.jpg")
        try Data("not an image".utf8).write(to: junk)

        XCTAssertNil(Thumbnails.generate(from: junk))
        XCTAssertNil(Thumbnails.generate(from: Data("not an image".utf8)))
        XCTAssertNil(Thumbnails.generate(from: tempDirectory.appendingPathComponent("missing.jpg")))
    }

    // MARK: - Both collection sites

    /// Site one: a scanned folder fills thumbnails in asynchronously.
    func testScanningAFolderFillsInThumbnails() async throws {
        for name in ["a", "b"] {
            try Fixtures.writeJPEG(
                width: 64, height: 48, orientation: 1, named: "\(name).jpg", in: tempDirectory
            )
        }
        let collection = ImageCollection()
        collection.loadFromFolder(tempDirectory)

        try await waitUntil("thumbnails for every scanned file") {
            collection.items.count == 2 && collection.items.allSatisfy { $0.thumbnail != nil }
        }
        for item in collection.items {
            let thumb = try XCTUnwrap(item.thumbnail)
            XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height),
                                     CGFloat(Thumbnails.defaultMaxPixelSize))
        }
    }

    /// Site two: a Photos import builds its thumbnails asynchronously from the transferred bytes,
    /// while retaining a managed URL for relaunch durability.
    func testImportingFromDataAlsoProducesThumbnails() async throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "photo.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)

        let libraryFolder = try Fixtures.makeTempDirectory("LumoImportLibrary")
        let collection = ImageCollection(libraryFolderURL: libraryFolder)
        collection.addFromData([(name: "photo", data: data)])

        XCTAssertEqual(collection.items.count, 1)
        let item = try XCTUnwrap(collection.items.first)
        XCTAssertEqual(
            item.url?.deletingLastPathComponent().standardizedFileURL,
            libraryFolder.standardizedFileURL
        )
        try await waitUntil("the imported thumbnail") {
            collection.items.first?.thumbnail != nil
        }
        let thumb = try XCTUnwrap(collection.items.first?.thumbnail,
                                  "the data import must produce a thumbnail too")
        XCTAssertGreaterThan(thumb.size.height, thumb.size.width,
                             "and it must be upright, like the folder path's")
        XCTAssertTrue(collection.isActive)
    }

    // MARK: - Helpers

    @discardableResult
    private func writeSolidPNG(named name: String, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        let image = try Fixtures.makeCGImage(width: 64, height: 64, red: red, green: green, blue: blue)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// The mean RGB of a thumbnail, so a mislabelled one is visible.
    private func dominantChannel(of image: NSImage) throws -> (Int, Int, Int) {
        var rect = CGRect(origin: .zero, size: image.size)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let bytes = try Pixels.bytes(of: cg)
        var r = 0, g = 0, b = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            r += Int(bytes[i]); g += Int(bytes[i + 1]); b += Int(bytes[i + 2])
        }
        let n = max(1, bytes.count / 4)
        return (r / n, g / n, b / n)
    }
}
