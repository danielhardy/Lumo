import XCTest
@testable import LUTzyKit

/// The gating the Step 10 ship gate names, expressed as a value rather than as a `ViewBuilder`.
///
/// This is why `availableControls` exists at all: the repo has no SwiftUI view tests and cannot
/// easily get them, so a gate written as `if capabilities.isDetailSupported` inside a view body
/// would be unverifiable. As an ordered array it is one assertion.
final class RAWCapabilitiesTests: XCTestCase {

    func testUngatedControlsAreAlwaysOffered() {
        // Every flag false — the worst decoder imaginable. The knobs that exist for every RAW
        // must still be there, or a supported camera would come up with an empty panel.
        let none = RAWCapabilities()
        let offered = Set(none.availableControls)

        for control: DevelopControl in [
            .exposure, .baselineExposure, .shadowBias, .boost, .boostShadow,
            .whiteBalance, .gamutMapping, .extendedDynamicRange,
        ] {
            XCTAssertTrue(offered.contains(control), "\(control.rawValue) is ungated and must always appear")
        }
    }

    func testGatedControlsAppearOnlyWhenSupported() {
        let none = RAWCapabilities()
        let offered = Set(none.availableControls)

        for control: DevelopControl in [
            .sharpness, .contrast, .detail, .moireReduction, .localToneMap,
            .luminanceNoiseReduction, .colorNoiseReduction, .lensCorrection, .highlightRecovery,
        ] {
            XCTAssertFalse(offered.contains(control), "\(control.rawValue) is gated and must be hidden")
        }

        XCTAssertEqual(
            Set(RAWCapabilities.everythingSupported.availableControls),
            Set(DevelopControl.allCases),
            "a decoder supporting everything should offer every control"
        )
    }

    /// One flag off, everything else on — the shape a real camera actually has, and the one a
    /// blanket `allCases` or a blanket `[]` would both pass.
    func testASingleUnsupportedAdjustmentIsTheOnlyOneMissing() {
        var caps = RAWCapabilities.everythingSupported
        caps.isLocalToneMapSupported = false

        XCTAssertFalse(caps.availableControls.contains(.localToneMap))
        XCTAssertEqual(
            Set(DevelopControl.allCases).subtracting(caps.availableControls), [.localToneMap],
            "exactly one control should have been withdrawn"
        )
    }

    /// Order is the panel's layout, so it is part of the contract rather than an accident of
    /// however the flags happen to be read.
    func testControlsComeOutInPanelOrder() {
        let all = RAWCapabilities.everythingSupported.availableControls
        XCTAssertEqual(all.first, .exposure, "tone leads the panel")
        XCTAssertEqual(
            all, DevelopControl.allCases,
            "availableControls must preserve the declared order, not re-sort it"
        )
    }

    func testEveryControlHasATitle() {
        for control in DevelopControl.allCases {
            XCTAssertFalse(control.title.isEmpty, "\(control.rawValue) has no label")
        }
    }
}
