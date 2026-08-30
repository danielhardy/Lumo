import XCTest
@testable import LumoKit

/// Covers the value-state spine introduced in Phase 2 Step 2: `EditDocument` and the two types it
/// composes that are pure values, `AdjustmentNode` and `LUTSettings`.
///
/// Nothing renders here — that is the point of Step 2. What is worth testing at this stage is
/// exactly what a later step would find painful to discover: that the document survives a
/// serialization round trip with its ordering intact, that a schema change has somewhere to hook
/// into, and that "empty document" really does mean "no-op".
final class EditDocumentTests: XCTestCase {

    private func roundTrip(_ document: EditDocument) throws -> EditDocument {
        let data = try JSONEncoder().encode(document)
        return try JSONDecoder().decode(EditDocument.self, from: data)
    }

    // MARK: - EditDocument round trip

    func testDefaultDocumentIsIdentityAndRoundTrips() throws {
        let document = EditDocument()

        XCTAssertEqual(document.version, 1, "version must ship at 1 from the first release")
        XCTAssertTrue(document.isIdentity, "an empty document must render the source unchanged")

        XCTAssertEqual(try roundTrip(document), document)
    }

    func testFullyPopulatedDocumentRoundTrips() throws {
        let document = EditDocument(
            rawDevelop: RAWDevelopSettings(
                exposure: 0.75,
                boostAmount: 0.5,
                neutralTemperature: 5200,
                neutralTint: -12,
                sharpnessAmount: 0.3,
                lensCorrectionEnabled: true,
                gamutMappingEnabled: false,
                extendedDynamicRangeAmount: 1.5,
                highlightRecoveryEnabled: true
            ),
            adjustments: [
                .exposure(ev: -0.5),
                .colorControls(brightness: 0.1, contrast: 1.2, saturation: 0.8),
                .highlightShadow(highlights: 0.6, shadows: 0.4),
                .temperatureTint(temp: 7000, tint: 5),
                .vibrance(amount: 0.25),
            ],
            lut: LUTSettings(lutID: LUTID(raw: "/Looks/Leica/VIV.cube"), intensity: 0.65)
        )

        let decoded = try roundTrip(document)

        // Whole-value equality is the real assertion; the field checks below exist so a failure
        // says which half moved rather than just "not equal".
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.rawDevelop, document.rawDevelop)
        XCTAssertEqual(decoded.adjustments, document.adjustments)
        XCTAssertEqual(decoded.lut.lutID?.raw, "/Looks/Leica/VIV.cube")
        XCTAssertEqual(decoded.lut.intensity, 0.65)
        XCTAssertFalse(decoded.isIdentity)
    }

    /// A `LUTID` is a newtype over a path, and its JSON should read like one — not `{"raw": "…"}`.
    /// A saved document is something a person may well end up looking at.
    func testLUTIDEncodesAsABareString() throws {
        let document = EditDocument(lut: LUTSettings(lutID: LUTID(raw: "/Looks/A.cube"), intensity: 1))
        let data = try JSONEncoder().encode(document)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let lut = try XCTUnwrap(object["lut"] as? [String: Any])
        XCTAssertEqual(lut["lutID"] as? String, "/Looks/A.cube",
                       "the ID should be a string, not a wrapper object: \(lut)")
    }

    // MARK: - Schema versioning

    /// Synthesized `Decodable` ignores property defaults, so every added field would break every
    /// older document. `decodeIfPresent` is what makes a v2 field optional for a v1 document — and
    /// this test is the thing that fails if someone deletes the hand-written `init(from:)` in favour
    /// of synthesis.
    func testAbsentFieldsFallBackToDefaults() throws {
        let data = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: data)

        XCTAssertEqual(decoded, EditDocument())
        XCTAssertEqual(decoded.version, EditDocument.currentVersion)
    }

    /// The other half of versioning: a document from a *newer* build is refused rather than
    /// silently narrowed. Opening a v2 document in a v1 build would drop whatever v2 added, and the
    /// next save would write that loss back over the user's edit.
    func testNewerSchemaVersionIsRejected() throws {
        let data = Data("{\"version\":\(EditDocument.currentVersion + 1)}".utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(EditDocument.self, from: data)) { error in
            // Assert on the *reason*, not merely that something threw: a decoder that failed for an
            // unrelated malformed-JSON reason would satisfy a bare throws check.
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("expected a dataCorrupted error, got \(error)")
            }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["version"])
            XCTAssertTrue(
                context.debugDescription.contains("newer version"),
                "the message should tell the user why: \(context.debugDescription)"
            )
        }

        // And the current version is not caught by the same guard.
        let current = Data("{\"version\":\(EditDocument.currentVersion)}".utf8)
        XCTAssertNoThrow(try JSONDecoder().decode(EditDocument.self, from: current))
    }

    // MARK: - AdjustmentNode ordering

    /// The adjustments array is a pipeline, not a set. `[exposure, saturation]` is a different render
    /// from the reverse, so both the value and its serialized form have to preserve the sequence
    /// exactly — including duplicates, which stack (`docs/PHASE2_SPEC.md` §8.6).
    func testAdjustmentOrderIsSignificantAndSurvivesEncoding() throws {
        let ordered: [AdjustmentNode] = [
            .exposure(ev: 1),
            .vibrance(amount: 0.5),
            .exposure(ev: -0.25),      // a duplicate case, deliberately
            .colorControls(brightness: 0, contrast: 1.4, saturation: 1),
        ]
        let document = EditDocument(adjustments: ordered)

        let decoded = try roundTrip(document)
        XCTAssertEqual(decoded.adjustments, ordered, "the sequence must survive verbatim")

        let reversed = EditDocument(adjustments: Array(ordered.reversed()))
        XCTAssertNotEqual(reversed, document, "reordering the pipeline is a different edit")
        XCTAssertNotEqual(reversed.adjustments, ordered)

        // Removing a duplicate is likewise a different edit — the two exposure nodes are not
        // redundant, they compose.
        let deduplicated = EditDocument(adjustments: [ordered[0], ordered[1], ordered[3]])
        XCTAssertNotEqual(deduplicated, document)
    }

    func testEachAdjustmentCaseRoundTripsIndependently() throws {
        let cases: [AdjustmentNode] = [
            .exposure(ev: 2.5),
            .colorControls(brightness: -0.2, contrast: 0.9, saturation: 1.6),
            .highlightShadow(highlights: 0.25, shadows: 0.75),
            .temperatureTint(temp: 3200, tint: 40),
            .vibrance(amount: -0.4),
        ]
        for node in cases {
            let data = try JSONEncoder().encode(node)
            XCTAssertEqual(try JSONDecoder().decode(AdjustmentNode.self, from: data), node)
        }
    }

    /// The identity values are the underlying `CIFilter` defaults, not a house convention. Getting
    /// one wrong would make the render skip a node that does something, or build a filter that does
    /// nothing.
    func testAdjustmentIdentityValuesMatchTheFilterDefaults() {
        XCTAssertTrue(AdjustmentNode.exposure(ev: 0).isIdentity)
        XCTAssertTrue(AdjustmentNode.colorControls(brightness: 0, contrast: 1, saturation: 1).isIdentity)
        XCTAssertTrue(AdjustmentNode.highlightShadow(highlights: 1, shadows: 0).isIdentity)
        XCTAssertTrue(AdjustmentNode.temperatureTint(temp: 6500, tint: 0).isIdentity)
        XCTAssertTrue(AdjustmentNode.vibrance(amount: 0).isIdentity)

        for node in [AdjustmentNode.neutralExposure, .neutralColorControls,
                     .neutralHighlightShadow, .neutralTemperatureTint, .neutralVibrance] {
            XCTAssertTrue(node.isIdentity, "\(node) is advertised as neutral")
        }

        // The near-misses: a zero contrast or zero saturation is a real edit, not a default.
        XCTAssertFalse(AdjustmentNode.exposure(ev: 0.01).isIdentity)
        XCTAssertFalse(AdjustmentNode.colorControls(brightness: 0, contrast: 0, saturation: 0).isIdentity)
        XCTAssertFalse(AdjustmentNode.highlightShadow(highlights: 0, shadows: 0).isIdentity)
        XCTAssertFalse(AdjustmentNode.temperatureTint(temp: 5000, tint: 0).isIdentity)
        XCTAssertFalse(AdjustmentNode.vibrance(amount: 0.1).isIdentity)
    }

    // MARK: - LUTSettings

    func testLUTSettingsIdentityRules() {
        XCTAssertTrue(LUTSettings.none.isIdentity)
        XCTAssertTrue(LUTSettings(lutID: LUTID(raw: "/a.cube"), intensity: 0).isIdentity,
                      "a LUT at zero strength contributes nothing")
        XCTAssertFalse(LUTSettings(lutID: LUTID(raw: "/a.cube"), intensity: 0.01).isIdentity)
        XCTAssertEqual(LUTSettings.none.intensity, 1.0, "the default strength is full, not zero")
    }

    func testDocumentIdentityTracksEveryComponent() {
        XCTAssertFalse(
            EditDocument(rawDevelop: RAWDevelopSettings(exposure: 0.5)).isIdentity,
            "a develop setting is an edit even with no adjustments and no LUT"
        )
        XCTAssertFalse(EditDocument(adjustments: [.exposure(ev: 1)]).isIdentity)
        XCTAssertTrue(
            EditDocument(adjustments: [.neutralExposure, .neutralVibrance]).isIdentity,
            "nodes left at their defaults are still a no-op"
        )
        XCTAssertFalse(
            EditDocument(lut: LUTSettings(lutID: LUTID(raw: "/a.cube"), intensity: 1)).isIdentity
        )
    }
}
