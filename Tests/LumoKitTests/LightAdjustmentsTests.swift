import XCTest
@testable import LumoKit

final class LightAdjustmentsTests: XCTestCase {

    private func roundTrip(_ value: LightAdjustments) throws -> LightAdjustments {
        try JSONDecoder().decode(LightAdjustments.self, from: JSONEncoder().encode(value))
    }

    func testNeutralLightIsIdentityAndHasPhotographerFacingRanges() {
        let light = LightAdjustments.neutral

        XCTAssertTrue(light.isIdentity)
        XCTAssertEqual(light.exposure, 0)
        XCTAssertEqual(light.contrast, 0)
        XCTAssertEqual(light.highlights, 0)
        XCTAssertEqual(light.shadows, 0)
        XCTAssertEqual(light.whites, 0)
        XCTAssertEqual(light.blacks, 0)
        XCTAssertTrue(light.toneCurve.isIdentity)
        XCTAssertEqual(LightAdjustments.exposureRange, -5...5)
        XCTAssertEqual(LightAdjustments.contrastRange, -100...100)
        XCTAssertEqual(LightAdjustments.highlightsRange, -100...100)
        XCTAssertEqual(LightAdjustments.shadowsRange, -100...100)
        XCTAssertEqual(LightAdjustments.whitesRange, -100...100)
        XCTAssertEqual(LightAdjustments.blacksRange, -100...100)
    }

    func testScalarsAreFiniteAndClampedAtConstructionAndMutation() {
        var light = LightAdjustments(
            exposure: .infinity,
            contrast: -.infinity,
            highlights: .nan,
            shadows: 200,
            whites: -200,
            blacks: 50
        )

        XCTAssertEqual(light.exposure, 0)
        XCTAssertEqual(light.contrast, 0)
        XCTAssertEqual(light.highlights, 0)
        XCTAssertEqual(light.shadows, 100)
        XCTAssertEqual(light.whites, -100)
        XCTAssertEqual(light.blacks, 50)

        light.exposure = 99
        light.contrast = -99
        light.highlights = .infinity
        light.shadows = .nan
        XCTAssertEqual(light.exposure, 5)
        XCTAssertEqual(light.contrast, -99)
        XCTAssertEqual(light.highlights, 0)
        XCTAssertEqual(light.shadows, 0)
    }

    func testToneCurveNormalizesPointsAndKeepsItsVersion() {
        let curve = LightToneCurve(version: 1, points: [
            LightCurvePoint(input: 0.8, output: 0.7),
            LightCurvePoint(input: 0.2, output: 0.3),
            LightCurvePoint(input: 0.2, output: 0.4),
            LightCurvePoint(input: 2, output: -.infinity),
        ])

        XCTAssertEqual(curve.points.map(\.input), [0, 0.2, 0.8, 1])
        XCTAssertEqual(curve.points[1].output, 0.4)
        XCTAssertEqual(curve.points[0].output, 0)
        XCTAssertEqual(curve.points[3].output, 0,
                       "the clamped duplicate at input 1 uses the last point's output")
        XCTAssertEqual(curve.version, LightToneCurve.currentVersion)
        XCTAssertFalse(curve.isIdentity)
    }

    func testLightCodableRoundTripIncludesCurve() throws {
        let light = LightAdjustments(
            exposure: 1.25,
            contrast: -35,
            highlights: 20,
            shadows: -40,
            whites: 15,
            blacks: -10,
            toneCurve: LightToneCurve(points: [
                LightCurvePoint(input: 0.25, output: 0.1),
                LightCurvePoint(input: 0.75, output: 0.9),
            ])
        )

        XCTAssertEqual(try roundTrip(light), light)
    }

    func testLegacyDocumentWithoutLightRetainsOldNodes() throws {
        let legacyJSON = """
        {
          "version": 1,
          "rawDevelop": {},
          "adjustments": [
            { "exposure": { "ev": 1.0 } },
            { "colorControls": { "brightness": 0.1, "contrast": 1.4, "saturation": 0.8 } },
            { "highlightShadow": { "highlights": 0.6, "shadows": 0.4 } }
          ],
          "lut": { "lutID": null, "intensity": 1.0 }
        }
        """

        let decoded = try JSONDecoder().decode(EditDocument.self, from: Data(legacyJSON.utf8))

        XCTAssertTrue(decoded.light.isIdentity)
        XCTAssertEqual(decoded.adjustments, [
            .exposure(ev: 1.0),
            .colorControls(brightness: 0.1, contrast: 1.4, saturation: 0.8),
            .highlightShadow(highlights: 0.6, shadows: 0.4),
        ])
    }

    func testEditHashIsStableAndIncludesLightState() throws {
        let base = EditDocument()
        let changed = EditDocument(light: LightAdjustments(exposure: 0.5))

        XCTAssertEqual(base.editHash, base.editHash)
        XCTAssertEqual(changed.editHash, try JSONDecoder().decode(
            EditDocument.self, from: JSONEncoder().encode(changed)
        ).editHash)
        XCTAssertNotEqual(base.editHash, changed.editHash)
    }
}
