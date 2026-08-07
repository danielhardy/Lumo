import XCTest
@testable import LUTzyKit

/// Phase 2 Step 10b. Pure-value tests: no engine, no `CIContext`, no image, no RAW — so all of this
/// runs on CI, which has none of those.
final class AdjustmentControlTests: XCTestCase {

    /// Every slot's neutral node must actually be an identity node — the base a write is applied to,
    /// and the value a read falls through to. The per-control half of this claim needs `value(in:)`
    /// and so lives in Task 4's `testEveryControlsNeutralMatchesTheNodesIdentity`.
    func testEverySlotsNeutralNodeIsAnIdentityNode() {
        for slot in AdjustmentSlot.allCases {
            XCTAssertTrue(slot.neutralNode.isIdentity,
                          "\(slot)'s neutral node must be an identity node")
            XCTAssertEqual(slot.neutralNode.slot, slot, "\(slot)'s neutral node is the wrong case")
        }
    }

    /// 10a's `testEveryPerImageSeedLandsStrictlyInsideItsSliderRange`, adapted — with the one
    /// exception the probe turned up.
    ///
    /// `CIHighlightShadowAdjust.inputHighlightAmount` has a slider floor of **0.3** and its identity
    /// is **1**, the range *maximum*. That is the filter's own definition, not a mistake here: the
    /// Highlights slider travels in one direction only, downward, recovering highlights. Every other
    /// control's neutral sits strictly inside its range, and this test says so control by control so
    /// that a second boundary case has to be added here deliberately.
    func testEveryNeutralSitsInsideItsRangeExceptHighlights() {
        for control in AdjustmentControl.allCases {
            XCTAssertTrue(
                control.range.contains(control.neutral),
                "\(control)'s neutral \(control.neutral) is outside its range \(control.range)"
            )
            if control == .highlights {
                XCTAssertEqual(control.neutral, control.range.upperBound,
                               "highlights' identity is documented to sit at the range maximum")
            } else {
                XCTAssertGreaterThan(control.neutral, control.range.lowerBound, "\(control)")
                XCTAssertLessThan(control.neutral, control.range.upperBound, "\(control)")
            }
        }
    }

    /// The nine controls are the five nodes' parameters, with none missed and none invented.
    func testEverySlotsControlsCoverItExactlyOnce() {
        XCTAssertEqual(AdjustmentControl.allCases.count, 9)
        let fromSlots = AdjustmentSlot.allCases.flatMap(\.controls)
        XCTAssertEqual(fromSlots, AdjustmentControl.allCases,
                       "slot order × within-slot order must equal declaration order")
    }

    /// Declaration order is layout order is canonical pipeline order — the order
    /// `RenderPipeline.applyAdjustments` folds. Pinned, because nothing else would notice it moving.
    func testSlotOrderMatchesTheNodeDeclarationOrder() {
        XCTAssertEqual(AdjustmentNode.neutralExposure.slot, .exposure)
        XCTAssertEqual(AdjustmentNode.neutralColorControls.slot, .colorControls)
        XCTAssertEqual(AdjustmentNode.neutralHighlightShadow.slot, .highlightShadow)
        XCTAssertEqual(AdjustmentNode.neutralTemperatureTint.slot, .temperatureTint)
        XCTAssertEqual(AdjustmentNode.neutralVibrance.slot, .vibrance)
        XCTAssertEqual(AdjustmentSlot.allCases.map(\.rawValue), [0, 1, 2, 3, 4])
    }

    /// Every title is human-facing and none is a `CIFilter` name.
    func testTitlesAreSetAndNotFilterNames() {
        for control in AdjustmentControl.allCases {
            XCTAssertFalse(control.title.isEmpty, "\(control) has no title")
            XCTAssertFalse(control.title.hasPrefix("CI"), "\(control)'s title is a filter name")
        }
    }
}
