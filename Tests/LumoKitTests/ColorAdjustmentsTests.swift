import XCTest
@testable import LumoKit

final class ColorAdjustmentsTests: XCTestCase {

    private func roundTrip(_ value: ColorAdjustments) throws -> ColorAdjustments {
        try JSONDecoder().decode(ColorAdjustments.self, from: JSONEncoder().encode(value))
    }

    func testNeutralValuesAndNormalizedMapping() {
        let neutral = ColorAdjustments.neutral
        XCTAssertTrue(neutral.isIdentity)
        XCTAssertEqual(neutral.normalizedVibrance, 0)
        XCTAssertEqual(neutral.normalizedSaturation, 1)
        XCTAssertEqual(ColorAdjustments(vibrance: -100, saturation: -100).normalizedVibrance, -1)
        XCTAssertEqual(ColorAdjustments(vibrance: 100, saturation: 100).normalizedVibrance, 1)
        XCTAssertEqual(ColorAdjustments(vibrance: 100, saturation: -100).normalizedSaturation, 0)
        XCTAssertEqual(ColorAdjustments(saturation: 100).normalizedSaturation, 2)
    }

    func testValuesAreFiniteAndClampedAtConstructionAndMutation() {
        var color = ColorAdjustments(vibrance: .infinity, saturation: -.infinity)
        XCTAssertEqual(color.vibrance, 0)
        XCTAssertEqual(color.saturation, 0)

        color.vibrance = .nan
        color.saturation = 200
        XCTAssertEqual(color.vibrance, 0)
        XCTAssertEqual(color.saturation, 100)
    }

    func testColorCodableRoundTripAndMissingValues() throws {
        let color = ColorAdjustments(vibrance: 42, saturation: -67)
        XCTAssertEqual(try roundTrip(color), color)
        XCTAssertEqual(
            try JSONDecoder().decode(ColorAdjustments.self, from: Data("{}".utf8)),
            .neutral
        )
    }

    func testDocumentColorIsIdentityAwareAndPersisted() throws {
        let document = EditDocument(color: ColorAdjustments(vibrance: 25, saturation: -30))
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: data)

        XCTAssertEqual(decoded.color, document.color)
        XCTAssertFalse(document.isIdentity)
        XCTAssertNotEqual(EditDocument().editHash, document.editHash)
    }

    func testOlderDocumentWithoutColorDefaultsToNeutral() throws {
        let data = Data("{\"version\":1,\"rawDevelop\":{},\"light\":{},\"adjustments\":[],\"lut\":{\"lutID\":null,\"intensity\":1}}".utf8)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(decoded.color, .neutral)
        XCTAssertTrue(decoded.color.isIdentity)
    }
}
