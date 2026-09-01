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

    func testToneCurveInterpolatesDeterministicallyAndClampsInput() {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0.25, output: 0.1),
            LightCurvePoint(input: 0.75, output: 0.9),
        ])

        XCTAssertEqual(curve.value(at: 0), 0, accuracy: 0.000_001)
        XCTAssertEqual(curve.value(at: 0.25), 0.1, accuracy: 0.000_001)
        XCTAssertEqual(curve.value(at: 0.5), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(curve.value(at: 0.75), 0.9, accuracy: 0.000_001)
        XCTAssertEqual(curve.value(at: 1), 1, accuracy: 0.000_001)
        XCTAssertEqual(curve.value(at: -1), 0, accuracy: 0.000_001)
        XCTAssertEqual(curve.value(at: 2), 1, accuracy: 0.000_001)
        XCTAssertEqual(curve.value(at: .nan), 0, accuracy: 0.000_001)
        XCTAssertTrue(curve.isMonotonic)
    }

    func testToneCurveUsesSmoothShapePreservingInterpolation() {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0.25, output: 0.2),
            LightCurvePoint(input: 0.5, output: 0.8),
        ])

        // A straight segment would return 0.5 here. The smooth curve bends locally toward the
        // moved middle control point while still passing through every control-point value.
        XCTAssertEqual(curve.value(at: 0.25), 0.2, accuracy: 0.000_001)
        XCTAssertEqual(curve.value(at: 0.5), 0.8, accuracy: 0.000_001)
        XCTAssertGreaterThan(curve.value(at: 0.375), 0.505,
                             "the moved handle should create a local smooth bend")
        XCTAssertLessThan(curve.value(at: 0.375), 0.53)

        let epsilon = 0.0001
        let leftDerivative = (curve.value(at: 0.25) - curve.value(at: 0.25 - epsilon)) / epsilon
        let rightDerivative = (curve.value(at: 0.25 + epsilon) - curve.value(at: 0.25)) / epsilon
        XCTAssertEqual(leftDerivative, rightDerivative, accuracy: 0.01,
                       "the interpolation should not introduce a visible kink at a handle")
    }

    func testToneCurveNeverOvershootsMonotonicControlPoints() {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0.11, output: 0.08),
            LightCurvePoint(input: 0.42, output: 0.36),
            LightCurvePoint(input: 0.77, output: 0.91),
        ])
        let values = (0...1_000).map { curve.value(at: Double($0) / 1_000) }

        for index in 1..<values.count {
            XCTAssertTrue(values[index].isFinite)
            XCTAssertGreaterThanOrEqual(values[index], values[index - 1] - 0.000_001,
                                        "a monotonic curve must not invert at sample \(index)")
        }

        for pair in zip(curve.points, curve.points.dropFirst()) {
            let samples = (0...100).map {
                let t = Double($0) / 100
                return curve.value(at: pair.0.input + t * (pair.1.input - pair.0.input))
            }
            XCTAssertGreaterThanOrEqual(samples.min()!, min(pair.0.output, pair.1.output) - 0.000_001)
            XCTAssertLessThanOrEqual(samples.max()!, max(pair.0.output, pair.1.output) + 0.000_001)
        }
    }

    func testToneCurveClickSamplesTheCurrentCurve() {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0.25, output: 0.1),
            LightCurvePoint(input: 0.75, output: 0.9),
        ])

        let clicked = curve.addingPoint(at: 0.5)

        XCTAssertEqual(clicked.points.map(\.input), [0, 0.25, 0.5, 0.75, 1])
        XCTAssertEqual(clicked.points[2].output, 0.5, accuracy: 0.000_001)
    }

    func testToneCurveRemovalOnlyChangesInteriorPoints() {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0.25, output: 0.1),
            LightCurvePoint(input: 0.75, output: 0.9),
        ])

        XCTAssertEqual(curve.removingPoint(at: 0), curve)
        XCTAssertEqual(curve.removingPoint(at: 1), curve)
        XCTAssertEqual(curve.removingPoint(at: 0.5), curve)
        XCTAssertEqual(curve.removingPoint(at: 0.74).points.map(\.input), [0, 0.25, 1])
    }

    func testToneCurveReportsNonMonotonicControlPointsWithoutRewritingThem() {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0.25, output: 0.8),
            LightCurvePoint(input: 0.75, output: 0.2),
        ])

        XCTAssertFalse(curve.isMonotonic)
        XCTAssertEqual(curve.points[1].output, 0.8)
        XCTAssertEqual(curve.points[2].output, 0.2)
    }

    func testToneCurveRejectsANewerSchemaVersion() throws {
        let data = Data("{\"version\":\(LightToneCurve.currentVersion + 1),\"points\":[]}".utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(LightToneCurve.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("expected a dataCorrupted error, got \(error)")
            }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["version"])
            XCTAssertTrue(context.debugDescription.contains("newer version"))
        }
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
        let curved = EditDocument(light: LightAdjustments(toneCurve: LightToneCurve(points: [
            LightCurvePoint(input: 0.5, output: 0.7),
        ])))

        XCTAssertEqual(base.editHash, base.editHash)
        XCTAssertEqual(changed.editHash, try JSONDecoder().decode(
            EditDocument.self, from: JSONEncoder().encode(changed)
        ).editHash)
        XCTAssertNotEqual(base.editHash, changed.editHash)
        XCTAssertNotEqual(base.editHash, curved.editHash,
                          "the master curve must participate in the persisted edit hash")
    }
}
