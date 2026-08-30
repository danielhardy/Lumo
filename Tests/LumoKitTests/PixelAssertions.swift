import XCTest
import CoreImage
import CoreGraphics
import simd
@testable import LumoKit

/// Shared pixel-level comparison for the render tests.
///
/// These started as private helpers inside `WorkingSpaceTests`; Step 3 needed the same gradient, the
/// same non-identity cube, and the same tolerance, and two copies of a comparison tolerance is exactly
/// the sort of thing that drifts until one suite is quietly weaker than the other.
enum Pixels {

    /// One context for the whole suite, so a comparison never accidentally measures two different
    /// render backends against each other.
    static let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext()
    }()

    /// Rasterize to raw RGBA8 in `space`.
    ///
    /// Note Core Image is **not** bit-reproducible across time-separated runs — around 0.0003% of
    /// bytes can move by 1 — while back-to-back runs match. Compare renders taken next to each other,
    /// and keep the tolerance at 1.
    static func bytes(of image: CIImage, space: WorkingSpace = .current) throws -> [UInt8] {
        let rect = image.extent.integral
        guard rect.isRasterizable else {
            throw XCTSkip("image has no rasterizable extent: \(image.extent)")
        }
        let width = Int(rect.width)
        let height = Int(rect.height)
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(
                image, toBitmap: base, rowBytes: width * 4, bounds: rect,
                format: .RGBA8, colorSpace: space.cgColorSpace
            )
        }
        return buffer
    }

    /// Rasterize a `CGImage` to raw RGBA8 **in its own colour space**, so the comparison itself
    /// introduces no conversion.
    static func bytes(of image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    /// Decode encoded bytes (a PNG, say) back to a `CGImage`.
    static func decode(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Largest per-byte difference, or `nil` if the buffers are different sizes.
    static func worstDelta(_ a: [UInt8], _ b: [UInt8]) -> (delta: Int, index: Int)? {
        guard a.count == b.count else { return nil }
        var worst = 0
        var index = -1
        for i in a.indices {
            let delta = abs(Int(a[i]) - Int(b[i]))
            if delta > worst { worst = delta; index = i }
        }
        return (worst, index)
    }
}

/// Both paths go through the GPU, and rounding at the 8-bit boundary can move a byte by one without
/// meaning anything diverged. Tolerance 1 is the house convention.
func assertPixelsEqual(
    _ a: [UInt8], _ b: [UInt8], tolerance: Int = 1, _ message: String,
    file: StaticString = #filePath, line: UInt = #line
) {
    guard let worst = Pixels.worstDelta(a, b) else {
        return XCTFail("\(message) — byte counts differ (\(a.count) vs \(b.count))", file: file, line: line)
    }
    XCTAssertLessThanOrEqual(
        worst.delta, tolerance,
        "\(message) — worst delta \(worst.delta) at byte \(worst.index)", file: file, line: line
    )
}

/// The inverse, and not merely `XCTAssertNotEqual`: a difference of 1 is noise, so "these differ" has
/// to mean *visibly* differ or the test would pass on rounding.
func assertPixelsDiffer(
    _ a: [UInt8], _ b: [UInt8], byAtLeast minimum: Int = 2, _ message: String,
    file: StaticString = #filePath, line: UInt = #line
) {
    guard let worst = Pixels.worstDelta(a, b) else {
        return  // different sizes is a difference
    }
    XCTAssertGreaterThanOrEqual(
        worst.delta, minimum,
        "\(message) — worst delta was only \(worst.delta)", file: file, line: line
    )
}

enum TestImages {

    /// A diagonal red→blue ramp. Exercises the gamut rather than one flat colour, so a colour-space
    /// or tone change actually shows up in the bytes.
    static func gradient(width: Int, height: Int) throws -> CIImage {
        let filter = try XCTUnwrap(CIFilter(name: "CILinearGradient"))
        filter.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        filter.setValue(CIVector(x: CGFloat(width), y: CGFloat(height)), forKey: "inputPoint1")
        filter.setValue(CIColor(red: 0.9, green: 0.1, blue: 0.1), forKey: "inputColor0")
        filter.setValue(CIColor(red: 0.1, green: 0.2, blue: 0.9), forKey: "inputColor1")
        let output = try XCTUnwrap(filter.outputImage)
        return output.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// The raw table of a cube that maps everything to black.
    ///
    /// Returned as values rather than a `CubeLUT` because the callers that want it are writing a
    /// `.cube` file — the loudest possible difference from an identity cube, which is what makes
    /// "did the new file reach the screen?" answerable in one comparison.
    static func toBlackCube(size: Int = 4) -> [SIMD3<Float>] {
        [SIMD3<Float>](repeating: .zero, count: size * size * size)
    }

    /// A cube that is emphatically not the identity: pushes red up and blue down, so both "the LUT
    /// ran" and "it interpolated in the right space" are visible.
    static func warmLUT(size: Int = 4, name: String = "warm") -> CubeLUT {
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
        return CubeLUT(cube: cube, size: size, name: name)
    }

    /// An identity cube — applying it must change nothing, which is what makes it useful for
    /// separating "the LUT stage ran" from "the LUT stage altered the image".
    static func identityLUT(size: Int = 4, name: String = "identity") -> CubeLUT {
        var cube = [SIMD3<Float>]()
        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    cube.append(SIMD3(Float(r) / denom, Float(g) / denom, Float(b) / denom))
                }
            }
        }
        return CubeLUT(cube: cube, size: size, name: name)
    }
}
