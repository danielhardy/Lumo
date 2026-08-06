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

    /// `supports(_:)` is nine near-identical `case .x: return isXSupported` arms, and the tests
    /// above cannot tell one arm from its neighbour: they either flip every gated flag together
    /// (`RAWCapabilities()`, `.everythingSupported`) or isolate only `.localToneMap`. A copy-paste
    /// slip that swaps, say, the `.contrast` and `.detail` arms passes every one of them.
    ///
    /// This drives every gated control through its own flag, one at a time, off a table so a
    /// mis-wired arm names itself in the failure rather than hiding behind an aggregate count.
    func testEachGatedControlIsWithdrawnByExactlyItsOwnFlag() {
        let gates: [(DevelopControl, WritableKeyPath<RAWCapabilities, Bool>)] = [
            (.sharpness, \.isSharpnessSupported),
            (.contrast, \.isContrastSupported),
            (.detail, \.isDetailSupported),
            (.moireReduction, \.isMoireReductionSupported),
            (.localToneMap, \.isLocalToneMapSupported),
            (.luminanceNoiseReduction, \.isLuminanceNoiseReductionSupported),
            (.colorNoiseReduction, \.isColorNoiseReductionSupported),
            (.lensCorrection, \.isLensCorrectionSupported),
            (.highlightRecovery, \.isHighlightRecoverySupported),
        ]

        // If a tenth gated flag ever joins `RAWCapabilities` without a row here, this catches the
        // omission instead of the new arm quietly riding along untested.
        let ungated: Set<DevelopControl> = [
            .exposure, .baselineExposure, .shadowBias, .boost, .boostShadow,
            .whiteBalance, .gamutMapping, .extendedDynamicRange,
        ]
        XCTAssertEqual(
            Set(gates.map(\.0)), Set(DevelopControl.allCases).subtracting(ungated),
            "the gate table must list exactly the gated controls, or a new flag would ship untested"
        )

        for (control, flag) in gates {
            var caps = RAWCapabilities.everythingSupported
            caps[keyPath: flag] = false

            let withdrawn = Set(DevelopControl.allCases).subtracting(caps.availableControls)
            XCTAssertEqual(
                withdrawn, [control],
                "\(control.rawValue)'s flag should withdraw only \(control.rawValue) — " +
                "supports(_:) is reading the wrong flag for this arm"
            )
        }
    }

    // MARK: - The real probe

    /// The flags a real decoder reports, read through the engine.
    ///
    /// Skips on CI, which has no DNG — read a green CI run as saying nothing about this.
    func testProbingARealRAWReportsItsDecodersFlags() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW; see Fixtures.localRAWURL and PHASE2_SPEC §8.9")
        }
        let engine = RenderEngine()
        let source = ImageSource(url: rawURL, nativeExtent: .zero)

        // `XCTUnwrap` takes an autoclosure, which cannot contain `await` — so the actor hop happens
        // here and the unwrap happens after it (see `RenderEngineTests.render`).
        let probed = await engine.rawCapabilities(for: source)
        let caps = try XCTUnwrap(probed)

        // Measured on the Leica DNG in realworldtest/. CODE_REVIEW §5 used to claim this file
        // "supports every one of them", which is why the gates were called untestable. It does not:
        // localToneMap is false, so the gated branch is coverable locally.
        XCTAssertFalse(caps.isLocalToneMapSupported,
                       "expected this decoder to refuse local tone mapping — if it now supports it, "
                       + "find another gate to pin rather than deleting this assertion")
        XCTAssertTrue(caps.isSharpnessSupported)
        XCTAssertTrue(caps.isColorNoiseReductionSupported)
        XCTAssertFalse(caps.availableControls.contains(.localToneMap),
                       "an unsupported adjustment must not be offered")

        // Seeds: as-shot WB is a real measured value, not a round default. If these came back 0 the
        // white-balance slider would open at 0 K.
        XCTAssertGreaterThan(caps.asShotTemperature, 2000)
        XCTAssertLessThan(caps.asShotTemperature, 50000)
    }

    /// A standard image has no CIRAWFilter to ask, and must not pretend otherwise.
    func testProbingAStandardImageReturnsNil() async throws {
        let directory = try Fixtures.makeTempDirectory("ProbeTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = try Fixtures.writeGradientPNG(width: 16, height: 16, named: "s.png", in: directory)

        let engine = RenderEngine()
        let caps = await engine.rawCapabilities(for: ImageSource(url: png, nativeExtent: .zero))

        XCTAssertNil(caps, "a JPEG or PNG has no develop stage; capabilities must be nil, not empty")
    }
}
