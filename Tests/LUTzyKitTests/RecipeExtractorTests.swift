import XCTest
import simd
import CoreGraphics
@testable import LUTzyKit

/// Covers the parts of the derive pipeline that can be tested without a RAW
/// fixture: the cube assembly (which decides what every unsampled color in the
/// image maps to) and the working-resolution cap.
final class RecipeExtractorTests: XCTestCase {

    // MARK: - buildCube

    /// A cell that received samples must come out as their mean, untouched by
    /// the neighbour smoothing.
    func testFilledCellsAveraging() {
        let size = 3
        let count = size * size * size
        var sums = [SIMD3<Float>](repeating: .zero, count: count)
        var counts = [Int32](repeating: 0, count: count)

        let index = 1 + 1 * size + 1 * size * size   // the middle cell
        sums[index] = SIMD3(0.6, 0.9, 1.2)           // three samples summing here
        counts[index] = 3

        let cube = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size, iterations: 0)

        XCTAssertEqual(cube[index].x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(cube[index].y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(cube[index].z, 0.4, accuracy: 0.0001)
    }

    /// With smoothing off, every unsampled cell falls back to identity — the
    /// color it started as — so an unseen color passes through unchanged rather
    /// than snapping to black.
    func testUnfilledCellsAnchorToIdentity() {
        let size = 4
        let count = size * size * size
        let cube = RecipeExtractor.buildCube(
            sums: [SIMD3<Float>](repeating: .zero, count: count),
            counts: [Int32](repeating: 0, count: count),
            size: size,
            iterations: 0
        )

        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let i = r + g * size + b * size * size
                    XCTAssertEqual(cube[i].x, Float(r) / denom, accuracy: 0.0001)
                    XCTAssertEqual(cube[i].y, Float(g) / denom, accuracy: 0.0001)
                    XCTAssertEqual(cube[i].z, Float(b) / denom, accuracy: 0.0001)
                }
            }
        }
    }

    /// One filled cell should bleed into its 26 immediate neighbours in a single
    /// smoothing pass — and no further.
    func testSmoothingPullsFromNeighboursOnePassAtATime() {
        let size = 5
        let count = size * size * size
        var sums = [SIMD3<Float>](repeating: .zero, count: count)
        var counts = [Int32](repeating: 0, count: count)

        let center = 2 + 2 * size + 2 * size * size
        sums[center] = SIMD3(1, 1, 1)
        counts[center] = 1

        let onePass = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size, iterations: 1)

        // A face neighbour of the center is inside the Moore neighbourhood.
        let adjacent = 3 + 2 * size + 2 * size * size
        XCTAssertEqual(onePass[adjacent].x, 1, accuracy: 0.0001,
                       "a direct neighbour should take the filled cell's value")

        // Two cells away is not, so after one pass it should still be identity.
        let distant = 4 + 2 * size + 2 * size * size
        XCTAssertEqual(onePass[distant].x, Float(4) / Float(size - 1), accuracy: 0.0001,
                       "smoothing should not reach two cells in a single pass")

        // A second pass reaches it.
        let twoPasses = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size, iterations: 2)
        XCTAssertEqual(twoPasses[distant].x, 1, accuracy: 0.0001,
                       "the second pass should carry the value one cell further")
    }

    /// Smoothing must read from the previous pass, not from cells filled
    /// earlier in the same pass — otherwise the result depends on iteration
    /// order and values race across the cube in one sweep.
    func testSmoothingIsNotOrderDependent() {
        let size = 5
        let count = size * size * size
        var sums = [SIMD3<Float>](repeating: .zero, count: count)
        var counts = [Int32](repeating: 0, count: count)

        // Seed the lowest corner; if a pass read its own writes, the value would
        // sweep the whole cube in one iteration because r/g/b ascend in order.
        sums[0] = SIMD3(1, 1, 1)
        counts[0] = 1

        let onePass = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size, iterations: 1)

        let twoAway = 2   // (r=2, g=0, b=0)
        XCTAssertEqual(onePass[twoAway].x, Float(2) / Float(size - 1), accuracy: 0.0001,
                       "one pass must not propagate through cells filled during the same pass")
    }

    func testBuiltCubeIsAlwaysFullyPopulatedAndFinite() {
        let size = 6
        let count = size * size * size
        var sums = [SIMD3<Float>](repeating: .zero, count: count)
        var counts = [Int32](repeating: 0, count: count)

        // Sparse, realistic-ish coverage: a handful of scattered cells.
        for i in stride(from: 0, to: count, by: 37) {
            sums[i] = SIMD3(0.5, 0.5, 0.5)
            counts[i] = 1
        }

        let cube = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size, iterations: 8)
        XCTAssertEqual(cube.count, count)
        for (i, v) in cube.enumerated() {
            XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite, "cell \(i) is not finite: \(v)")
        }
    }

    // MARK: - Working resolution

    func testWorkingSizeCapsLongEdgeAndKeepsAspect() {
        let capped = RecipeExtractor.workingSize(
            for: CGSize(width: 9000, height: 6000), longEdge: 3000
        )
        XCTAssertEqual(capped.width, 3000)
        XCTAssertEqual(capped.height, 2000)
    }

    func testWorkingSizeCapsPortraitOnItsLongEdge() {
        let capped = RecipeExtractor.workingSize(
            for: CGSize(width: 6000, height: 9000), longEdge: 3000
        )
        XCTAssertEqual(capped.height, 3000)
        XCTAssertEqual(capped.width, 2000)
    }

    func testWorkingSizeLeavesSmallImagesAlone() {
        let size = CGSize(width: 1200, height: 800)
        XCTAssertEqual(RecipeExtractor.workingSize(for: size, longEdge: 3000), size,
                       "an image already under the cap should not be upscaled")
    }

    func testWorkingSizeZeroMeansNative() {
        let size = CGSize(width: 9000, height: 6000)
        XCTAssertEqual(RecipeExtractor.workingSize(for: size, longEdge: 0), size)
        XCTAssertEqual(RecipeExtractor.workingSize(for: size, longEdge: -1), size)
    }

    // MARK: - Errors

    func testGeometryMismatchErrorNamesBothSizes() throws {
        let error = RecipeExtractor.ExtractorError.geometryMismatch(
            raw: CGSize(width: 4928, height: 3288),
            jpg: CGSize(width: 533, height: 800)
        )
        let message = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(message.contains("4928×3288"), "should name the RAW size: \(message)")
        XCTAssertTrue(message.contains("533×800"), "should name the JPG size: \(message)")
    }
}
