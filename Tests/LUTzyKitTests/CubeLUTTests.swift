import XCTest
import CoreImage
import simd
@testable import LUTzyKit

/// The `.cube` parser is the one place LUTzy ingests third-party files, so it
/// gets the most adversarial coverage: malformed sizes, degenerate domains,
/// vendor line endings, and the index ordering that a transposed cube would
/// silently corrupt.
final class CubeLUTTests: TempDirectoryTestCase {

    // MARK: - Parsing

    func testParsesIdentityCube() throws {
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 8), named: "identity.cube", in: tempDirectory
        )
        let lut = try CubeLUT(url: url)

        XCTAssertEqual(lut.size, 8)
        XCTAssertEqual(lut.category, "General")
        XCTAssertEqual(lut.id, url.path, "id should be the file path for file-backed LUTs")
    }

    func testParsesCRLFLineEndings() throws {
        // Several shipped LUTs in this repo's own LUTS/ folder are CRLF.
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 4),
            named: "crlf.cube",
            in: tempDirectory,
            lineEnding: "\r\n"
        )
        let lut = try CubeLUT(url: url)
        XCTAssertEqual(lut.size, 4)
        XCTAssertNotNil(lut.makeFilter(), "a CRLF cube must still produce a usable filter")
    }

    func testMissingSizeThrows() throws {
        let text = """
            TITLE "no size"
            0.0 0.0 0.0
            1.0 1.0 1.0
            """
        let url = try Fixtures.writeCube(text, named: "nosize.cube", in: tempDirectory)
        XCTAssertThrowsError(try CubeLUT(url: url)) { error in
            guard case LUTError.invalidFormat(let message) = error else {
                return XCTFail("expected .invalidFormat, got \(error)")
            }
            XCTAssertTrue(message.contains("LUT_3D_SIZE"))
        }
    }

    func testWrongEntryCountThrows() throws {
        // Declares 8³ = 512 entries but supplies two.
        let text = """
            LUT_3D_SIZE 8
            0.0 0.0 0.0
            1.0 1.0 1.0
            """
        let url = try Fixtures.writeCube(text, named: "short.cube", in: tempDirectory)
        XCTAssertThrowsError(try CubeLUT(url: url)) { error in
            guard case LUTError.invalidFormat(let message) = error else {
                return XCTFail("expected .invalidFormat, got \(error)")
            }
            XCTAssertTrue(message.contains("512"), "message should name the expected count: \(message)")
            XCTAssertTrue(message.contains("2"), "message should name the actual count: \(message)")
        }
    }

    func testCommentsAndBlankLinesAreIgnored() throws {
        var text = Fixtures.identityCubeText(size: 2)
        text = "# leading comment\n\n" + text + "\n# trailing comment\n\n"
        let url = try Fixtures.writeCube(text, named: "comments.cube", in: tempDirectory)
        XCTAssertEqual(try CubeLUT(url: url).size, 2)
    }

    // MARK: - Domain handling

    func testDomainIsNormalizedToUnitRange() throws {
        // A cube whose data spans 0…2 with DOMAIN_MAX 2 must normalize to the
        // same table as the equivalent 0…1 cube.
        let text = """
            LUT_3D_SIZE 2
            DOMAIN_MIN 0.0 0.0 0.0
            DOMAIN_MAX 2.0 2.0 2.0
            0.0 0.0 0.0
            2.0 0.0 0.0
            0.0 2.0 0.0
            2.0 2.0 0.0
            0.0 0.0 2.0
            2.0 0.0 2.0
            0.0 2.0 2.0
            2.0 2.0 2.0
            """
        let url = try Fixtures.writeCube(text, named: "domain.cube", in: tempDirectory)
        let scaled = try CubeLUT(url: url)

        let identityURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "unit.cube", in: tempDirectory
        )
        let identity = try CubeLUT(url: identityURL)

        // Both should map a mid-gray to the same output.
        let probe = solidImage(red: 0.5, green: 0.5, blue: 0.5)
        let a = try XCTUnwrap(render(try XCTUnwrap(scaled.apply(to: probe))))
        let b = try XCTUnwrap(render(try XCTUnwrap(identity.apply(to: probe))))
        XCTAssertEqual(a.0, b.0, accuracy: 2)
        XCTAssertEqual(a.1, b.1, accuracy: 2)
        XCTAssertEqual(a.2, b.2, accuracy: 2)
    }

    /// Regression for B12: a domain with min == max divided by zero and filled
    /// that axis of the table with NaN.
    ///
    /// This has to be asserted on the parsed table, not on rendered output:
    /// Core Image clamps NaN to 0 when rasterizing, so a fully corrupt table
    /// still renders a plausible-looking black and an output-side check passes.
    func testDegenerateDomainDoesNotProduceNaN() throws {
        let entries = Fixtures.identityCubeText(size: 2)
            .split(separator: "\n")
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("TITLE") && !$0.hasPrefix("LUT_3D_SIZE") }
            .joined(separator: "\n")
        let text = """
            LUT_3D_SIZE 2
            DOMAIN_MIN 0.5 0.0 0.0
            DOMAIN_MAX 0.5 1.0 1.0
            """ + "\n" + entries

        let url = try Fixtures.writeCube(text, named: "degenerate.cube", in: tempDirectory)
        let lut = try CubeLUT(url: url)

        let table = lut.tableFloats
        XCTAssertEqual(table.count, 2 * 2 * 2 * 4)
        for (i, value) in table.enumerated() {
            XCTAssertTrue(value.isFinite, "table entry \(i) is \(value); a degenerate axis must not yield NaN")
        }

        // The collapsed axis should fall back to the default 0…1 range, so the
        // cube still behaves like the identity it was written as.
        XCTAssertEqual(table[0], 0, accuracy: 0.0001, "first cell red should be 0")
        XCTAssertEqual(table[4], 1, accuracy: 0.0001, "second cell red should be 1")
    }

    // MARK: - Naming

    func testStripsVendorSuffixesFromDisplayName() throws {
        for (fileName, expected) in [
            ("Ricoh_GR2_Posi_33_Rec709.cube", "Ricoh_GR2_Posi"),
            ("Something_65_Rec709.cube", "Something"),
            ("Plain_Rec709.cube", "Plain"),
            ("Untouched.cube", "Untouched"),
        ] {
            let url = try Fixtures.writeCube(
                Fixtures.identityCubeText(size: 2), named: fileName, in: tempDirectory
            )
            XCTAssertEqual(try CubeLUT(url: url).name, expected)
        }
    }

    // MARK: - Index ordering

    /// The .cube format and Core Image both expect R varying fastest, then G,
    /// then B. A transposed cube still parses and still renders — it just
    /// silently swaps channels — so this pins the ordering with an asymmetric
    /// cube that maps everything to pure red only in one corner.
    func testIndexOrderingIsRedFastest() throws {
        let size = 2
        var lines = ["LUT_3D_SIZE \(size)"]
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    // Output = 1 only at (r=1, g=0, b=0): the second entry.
                    let on = (r == 1 && g == 0 && b == 0)
                    lines.append(on ? "1.0 1.0 1.0" : "0.0 0.0 0.0")
                }
            }
        }
        let url = try Fixtures.writeCube(
            lines.joined(separator: "\n") + "\n", named: "ordering.cube", in: tempDirectory
        )
        let lut = try CubeLUT(url: url)

        // Pure red input should land on that corner and come out white.
        let red = try XCTUnwrap(render(try XCTUnwrap(lut.apply(to: solidImage(red: 1, green: 0, blue: 0)))))
        XCTAssertGreaterThan(red.0, 200, "pure red should hit the (1,0,0) cell → white")

        // Pure blue should not.
        let blue = try XCTUnwrap(render(try XCTUnwrap(lut.apply(to: solidImage(red: 0, green: 0, blue: 1)))))
        XCTAssertLessThan(blue.0, 55, "pure blue should hit a zeroed cell → black")
    }

    // MARK: - Writing / round-trip

    func testWriteThenParseRoundTrips() throws {
        let size = 5
        var cube = [SIMD3<Float>]()
        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    // A non-identity but reproducible mapping.
                    cube.append(SIMD3(
                        Float(r) / denom * 0.5,
                        Float(g) / denom,
                        Float(b) / denom * 0.25
                    ))
                }
            }
        }

        let url = tempDirectory.appendingPathComponent("roundtrip.cube")
        try CubeLUT.write(cube: cube, size: size, title: "roundtrip", to: url)
        let parsed = try CubeLUT(url: url)

        XCTAssertEqual(parsed.size, size)
        XCTAssertEqual(parsed.name, "roundtrip")

        // Compare against an in-memory LUT built from the same values: both must
        // grade an image identically.
        let inMemory = CubeLUT(cube: cube, size: size, name: "memory")
        let probe = solidImage(red: 0.75, green: 0.5, blue: 0.25)
        let fromFile = try XCTUnwrap(render(try XCTUnwrap(parsed.apply(to: probe))))
        let fromMemory = try XCTUnwrap(render(try XCTUnwrap(inMemory.apply(to: probe))))
        XCTAssertEqual(fromFile.0, fromMemory.0, accuracy: 2)
        XCTAssertEqual(fromFile.1, fromMemory.1, accuracy: 2)
        XCTAssertEqual(fromFile.2, fromMemory.2, accuracy: 2)
    }

    func testWriteClampsOutOfRangeValues() throws {
        let cube = [SIMD3<Float>](repeating: SIMD3(-1, 2, 0.5), count: 8)
        let text = CubeLUT.cubeFileContents(cube: cube, size: 2, title: "clamped")
        for line in text.split(separator: "\n") where !line.contains(where: { $0.isLetter || $0 == "#" }) {
            let values = line.split(separator: " ").compactMap { Float($0) }
            guard values.count == 3 else { continue }
            XCTAssertEqual(values[0], 0, "negative values should clamp to 0")
            XCTAssertEqual(values[1], 1, "values above 1 should clamp to 1")
            XCTAssertEqual(values[2], 0.5, accuracy: 0.0001)
        }
    }

    // MARK: - Intensity

    /// A LUT at intensity 0 must be a no-op, at 1 the full grade, and in
    /// between a blend — this is what the toolbar slider rides on.
    func testIntensityBlendsBetweenOriginalAndGraded() throws {
        // A cube that maps everything to black makes the blend easy to read.
        let size = 2
        let cube = [SIMD3<Float>](repeating: .zero, count: size * size * size)
        let lut = CubeLUT(cube: cube, size: size, name: "toBlack")

        let probe = solidImage(red: 1, green: 1, blue: 1)

        let none = try XCTUnwrap(render(try XCTUnwrap(lut.apply(to: probe, intensity: 0))))
        XCTAssertGreaterThan(none.0, 240, "intensity 0 should leave the original untouched")

        let full = try XCTUnwrap(render(try XCTUnwrap(lut.apply(to: probe, intensity: 1))))
        XCTAssertLessThan(full.0, 15, "intensity 1 should be the full grade")

        let half = try XCTUnwrap(render(try XCTUnwrap(lut.apply(to: probe, intensity: 0.5))))
        XCTAssertTrue((60...200).contains(Int(half.0)),
                      "intensity 0.5 should land between the two, got \(half.0)")
    }

    func testIntensityIsClampedToUnitRange() throws {
        let cube = [SIMD3<Float>](repeating: .zero, count: 8)
        let lut = CubeLUT(cube: cube, size: 2, name: "toBlack")
        let probe = solidImage(red: 1, green: 1, blue: 1)

        let below = try XCTUnwrap(render(try XCTUnwrap(lut.apply(to: probe, intensity: -5))))
        XCTAssertGreaterThan(below.0, 240, "negative intensity should behave as 0")

        let above = try XCTUnwrap(render(try XCTUnwrap(lut.apply(to: probe, intensity: 5))))
        XCTAssertLessThan(above.0, 15, "intensity above 1 should behave as 1")
    }

    // MARK: - In-memory init

    func testInMemoryLUTGetsSyntheticIDWhenNotFileBacked() {
        let cube = [SIMD3<Float>](repeating: .zero, count: 8)
        let a = CubeLUT(cube: cube, size: 2, name: "derived")
        let b = CubeLUT(cube: cube, size: 2, name: "derived")
        XCTAssertTrue(a.id.hasPrefix("derived://"))
        XCTAssertNotEqual(a.id, b.id, "two in-memory LUTs must not collide as the same identity")
    }

    func testEqualityAndHashingUseIdentityNotContents() throws {
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "same.cube", in: tempDirectory
        )
        let a = try CubeLUT(url: url)
        let b = try CubeLUT(url: url)
        XCTAssertEqual(a, b, "same path should compare equal — sidebar selection depends on it")
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    // MARK: - Helpers

    private func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    /// Render one pixel of `image` as 8-bit sRGB.
    private func render(_ image: CIImage) -> (CGFloat, CGFloat, CGFloat)? {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        var bytes = [UInt8](repeating: 0, count: 4)
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        bytes.withUnsafeMutableBytes { ptr in
            context.render(
                image, toBitmap: ptr.baseAddress!, rowBytes: 4, bounds: rect,
                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            )
        }
        return (CGFloat(bytes[0]), CGFloat(bytes[1]), CGFloat(bytes[2]))
    }
}
