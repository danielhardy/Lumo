import XCTest
import CoreImage
@testable import LUTzyKit

/// The cache exists because handing Core Image a 65³ cube — ~4.4 MB — on every frame of a slider drag
/// is waste. What has to be true for it to be safe:
///
/// - the key includes the colour space, or the `WorkingSpace` seam is silently broken;
/// - a reused `CIFilter` does not retroactively change images already built from it;
/// - it does not grow without bound, because each entry is megabytes.
final class LUTFilterCacheTests: XCTestCase {

    // MARK: - Reuse

    func testTheSameLUTAndSpaceReturnsTheSameFilter() {
        let cache = LUTFilterCache()
        let lut = TestImages.warmLUT()

        let first = cache.filter(for: lut, space: .sRGB)
        let second = cache.filter(for: lut, space: .sRGB)

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "a cache hit should hand back the same instance")
        XCTAssertEqual(cache.count, 1, "and should not have built a second one")
    }

    /// The cube is interpolated *in* the colour space, so the same LUT in two spaces is two different
    /// filters. Keying on the LUT alone would hand back an sRGB cube for a P3 render and quietly
    /// break the lockstep that `WorkingSpace` exists to guarantee.
    func testTheColourSpaceIsPartOfTheKey() throws {
        let cache = LUTFilterCache()
        let lut = TestImages.warmLUT()

        let sRGB = try XCTUnwrap(cache.filter(for: lut, space: .sRGB))
        let p3 = try XCTUnwrap(cache.filter(for: lut, space: .displayP3))

        XCTAssertFalse(sRGB === p3, "two spaces must not share one filter")
        XCTAssertEqual(cache.count, 2)

        // And the filters really are configured differently, not just distinct objects.
        let sRGBSpace = sRGB.value(forKey: "inputColorSpace")
        let p3Space = p3.value(forKey: "inputColorSpace")
        XCTAssertEqual((sRGBSpace as! CGColorSpace).name, CGColorSpace.sRGB)
        XCTAssertEqual((p3Space as! CGColorSpace).name, CGColorSpace.displayP3)
    }

    /// Two different LUTs are two different entries — keyed by `LUTID`, which is the file path, so
    /// this also pins that the cache is not accidentally keyed on something like the display name.
    func testDifferentLUTsGetDifferentFilters() throws {
        let cache = LUTFilterCache()
        let warm = TestImages.warmLUT(name: "warm")
        let identity = TestImages.identityLUT(name: "identity")

        let a = try XCTUnwrap(cache.filter(for: warm))
        let b = try XCTUnwrap(cache.filter(for: identity))

        XCTAssertFalse(a === b)
        XCTAssertEqual(cache.count, 2)
    }

    // MARK: - The assumption the whole design rests on

    /// Reusing a `CIFilter` means writing `inputImage` to it again. That is only safe because
    /// `outputImage` snapshots the inputs into an immutable graph rather than reading them lazily at
    /// render time — if it were lazy, every image previously built from the cached filter would
    /// silently change the next time the filter was reused.
    ///
    /// This is asserted against real Core Image rather than taken on faith, because the entire cache
    /// is unsound if it is false.
    func testOutputImageSnapshotsItsInputsRatherThanReadingThemLater() throws {
        let cache = LUTFilterCache()
        let lut = TestImages.warmLUT()
        let filter = try XCTUnwrap(cache.filter(for: lut))

        let first = try TestImages.gradient(width: 32, height: 32)
        let second = try TestImages.gradient(width: 32, height: 32)
            .applyingFilter("CIColorInvert")

        filter.setValue(first, forKey: kCIInputImageKey)
        let outputFromFirst = try XCTUnwrap(filter.outputImage)
        // Capture the bytes now, while the filter still holds `first`.
        let beforeReuse = try Pixels.bytes(of: outputFromFirst)

        // Reuse the same filter for a different image — exactly what a cache hit does.
        filter.setValue(second, forKey: kCIInputImageKey)
        let outputFromSecond = try XCTUnwrap(filter.outputImage)
        let afterReuse = try Pixels.bytes(of: outputFromFirst)

        assertPixelsEqual(afterReuse, beforeReuse,
                          "reusing a cached filter must not retroactively alter an image already built from it")
        assertPixelsDiffer(try Pixels.bytes(of: outputFromSecond), beforeReuse,
                           "and the second image should reflect the new input")
    }

    // MARK: - Bounds

    func testTheCacheIsBoundedAndEvictsTheLeastRecentlyUsed() throws {
        let cache = LUTFilterCache(capacity: 3)
        let luts = (0..<4).map { TestImages.warmLUT(name: "lut-\($0)") }

        let zero = try XCTUnwrap(cache.filter(for: luts[0]))
        _ = cache.filter(for: luts[1])
        _ = cache.filter(for: luts[2])
        XCTAssertEqual(cache.count, 3)

        // Touch 0 so it is the most recent, making 1 the least recent.
        XCTAssertTrue(cache.filter(for: luts[0]) === zero, "still cached before the overflow")

        _ = cache.filter(for: luts[3])
        XCTAssertEqual(cache.count, 3, "capacity must hold")

        XCTAssertTrue(cache.filter(for: luts[0]) === zero, "0 was used most recently and should survive")
        XCTAssertEqual(cache.count, 3)
    }

    func testCapacityIsAtLeastOne() {
        // A zero or negative capacity would evict the entry it just inserted, making every lookup a
        // miss and the cache pure overhead.
        let cache = LUTFilterCache(capacity: 0)
        let lut = TestImages.warmLUT()

        let first = cache.filter(for: lut)
        XCTAssertNotNil(first)
        XCTAssertTrue(cache.filter(for: lut) === first, "even the smallest cache must hold one entry")
    }

    func testRemoveAllDropsEverything() throws {
        let cache = LUTFilterCache()
        let lut = TestImages.warmLUT()
        let first = try XCTUnwrap(cache.filter(for: lut))
        XCTAssertEqual(cache.count, 1)

        cache.removeAll()
        XCTAssertEqual(cache.count, 0)

        // A LUTID is a file path, so a .cube edited in place keeps its ID. `removeAll` is how the
        // stale cube gets dropped — a rebuilt filter must therefore be a new instance.
        let rebuilt = try XCTUnwrap(cache.filter(for: lut))
        XCTAssertFalse(rebuilt === first, "after a flush the filter should be rebuilt, not resurrected")
    }
}
