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

    // MARK: - Toggle and range, which are now the enum's own business

    /// `isToggle` decides whether a control gets a `Toggle` or a `Slider`, and whether its write is
    /// immediate or debounced. Both switches lost their `default:` arm so an eighteenth case is a
    /// compile error rather than a silent 0…1 slider — but the compiler cannot tell a *mis-assigned*
    /// case from a correct one, so pin the whole partition here.
    func testExactlyTheBoolBackedControlsAreToggles() {
        let expected: Set<DevelopControl> = [.lensCorrection, .gamutMapping, .highlightRecovery]
        let actual = Set(DevelopControl.allCases.filter(\.isToggle))
        XCTAssertEqual(
            actual, expected,
            "a toggle is exactly a control whose RAWDevelopSettings property is Bool? — a slider "
            + "bound to a Bool writes 0.37 into a checkbox, and a toggle bound to a Double is stuck "
            + "at its two ends"
        )
    }

    /// Every control's range, written out.
    ///
    /// The point of moving `range` next to `RAWDevelopSettings` was to put each literal one file from
    /// the doc comment it has to match; this is the check that makes that worth doing. Values marked
    /// *documented* come from `CIRAWFilter` via `RAWDevelopSettings`' per-property comments and
    /// `PHASE2_SPEC.md` §9. Values marked *ours* are UI choices with no documented bound — see
    /// `DevelopControl.range`'s doc comment. Changing a documented row should require changing the
    /// doc comment it contradicts; changing one of ours is free, and this table is just the record.
    func testEveryControlsSliderRangeIsPinned() {
        let expected: [DevelopControl: ClosedRange<Double>] = [
            .exposure: -4...4,                    // ours
            .baselineExposure: -4...4,            // ours
            .shadowBias: -10...10,                // ours
            .boost: 0...1,                        // documented: "Global tone curve, 0…1"
            .boostShadow: 0...2,                  // documented: "0…2 (<1 darkens, >1 lightens)"
            .whiteBalance: 2000...50000,          // documented: "2000…50000 K"
            .sharpness: 0...1,                    // documented
            .contrast: 0...1,                     // documented: "Local contrast, 0…1"
            .detail: 0...3,                       // documented: "Detail enhancement, 0…3"
            .moireReduction: 0...1,               // documented
            .localToneMap: 0...1,                 // documented: "Local tone curve, 0…1"
            .luminanceNoiseReduction: 0...1,      // documented
            .colorNoiseReduction: 0...1,          // documented
            .lensCorrection: 0...1,               // toggle, expressed as 0/1
            .gamutMapping: 0...1,                 // toggle
            .extendedDynamicRange: 0...2,         // documented: "0…2 (0 = no EDR … 2 = maximum)"
            .highlightRecovery: 0...1,            // toggle
        ]

        // A new case must arrive with a row, not inherit one.
        XCTAssertEqual(
            Set(expected.keys), Set(DevelopControl.allCases),
            "the range table must cover every control exactly once"
        )

        for control in DevelopControl.allCases {
            XCTAssertEqual(
                control.range, expected[control],
                "\(control.rawValue)'s slider range moved — if that was deliberate, update the "
                + "doc comment on DevelopControl.range in the same commit"
            )
        }

        XCTAssertNotEqual(
            DevelopControl.boost.range, DevelopControl.boostShadow.range,
            "boost is 0…1 and boostShadow is 0…2; sharing an arm would let boost reach 2.0"
        )
        XCTAssertEqual(DevelopControl.tintRange, -150...150, "documented as −150…150")
    }

    /// A toggle's value is carried as 0 or 1 through a `Binding<Double>`, so its range has to contain
    /// both — a 0…1 range is not decoration here.
    func testEveryToggleRangeSpansItsTwoStates() {
        for control in DevelopControl.allCases where control.isToggle {
            XCTAssertTrue(control.range.contains(0) && control.range.contains(1),
                          "\(control.rawValue) is a toggle; its range must hold both states")
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

    /// The *seeds* a real decoder reports for the eight gated adjustments.
    ///
    /// These eight used to be read back as a hardcoded `0` (and `true` for lens correction), which is
    /// the same defect the white-balance seed exists to prevent: `RAWDevelopSettings`' type doc says
    /// the noise-reduction and sharpening defaults **vary per image**, so a guessed constant opens
    /// the slider away from where the picture is and the first nudge jumps it.
    ///
    /// Skips on CI, which has no DNG — read a green CI run as saying nothing about this.
    func testProbingARealRAWReportsItsDecodersSeeds() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW; see Fixtures.localRAWURL and PHASE2_SPEC §8.9")
        }
        let engine = RenderEngine()
        let source = ImageSource(url: rawURL, nativeExtent: .zero)
        let probed = await engine.rawCapabilities(for: source)
        let caps = try XCTUnwrap(probed)

        // Printed so the next person can see the decoder's own answer rather than trusting the
        // numbers written below, which are only a snapshot of one file on one macOS build.
        print("""
        --- Leica M11 DNG (realworldtest/20260525_102528_L1031183.DNG), as probed ---
          asShotTemperature            \(caps.asShotTemperature)
          asShotTint                   \(caps.asShotTint)
          baselineExposure             \(caps.baselineExposure)
          shadowBias                   \(caps.shadowBias)
          sharpnessAmount              \(caps.sharpnessAmount)   \
        (supported: \(caps.isSharpnessSupported))
          contrastAmount               \(caps.contrastAmount)   \
        (supported: \(caps.isContrastSupported))
          detailAmount                 \(caps.detailAmount)   \
        (supported: \(caps.isDetailSupported))
          moireReductionAmount         \(caps.moireReductionAmount)   \
        (supported: \(caps.isMoireReductionSupported))
          localToneMapAmount           \(caps.localToneMapAmount)   \
        (supported: \(caps.isLocalToneMapSupported))
          luminanceNoiseReduction      \(caps.luminanceNoiseReductionAmount)   \
        (supported: \(caps.isLuminanceNoiseReductionSupported))
          colorNoiseReductionAmount    \(caps.colorNoiseReductionAmount)   \
        (supported: \(caps.isColorNoiseReductionSupported))
          lensCorrectionEnabled        \(caps.lensCorrectionEnabled)   \
        (supported: \(caps.isLensCorrectionSupported))
        ---------------------------------------------------------------------------
        """)

        // OBSERVED on the Leica M11 DNG, macOS 26 / Xcode 26 (the printout above is the live run):
        //
        //   asShotTemperature          5842.2119140625
        //   asShotTint                 14.039999961853027
        //   baselineExposure           0.4000000059604645
        //   shadowBias                 5.0
        //   sharpnessAmount            0.7349015474319458   supported
        //   contrastAmount             0.0                  supported
        //   detailAmount               0.0                  supported
        //   moireReductionAmount       0.0                  supported
        //   localToneMapAmount         0.0                  NOT supported — never queried
        //   luminanceNoiseReduction    0.0                  supported
        //   colorNoiseReductionAmount  0.5                  supported
        //   lensCorrectionEnabled      true                 supported
        //
        // `sharpnessAmount` is the finding in one number. 0.7349015474319458 is not a constant
        // anybody would guess; it is computed per image, exactly as `RAWDevelopSettings`' type doc
        // warns. The old getter opened that slider at 0 — three quarters of the way from where the
        // picture actually was — so the first touch of it jumped the image hard.
        // `colorNoiseReductionAmount` at 0.5 is the same defect, smaller.
        //
        // Note also `shadowBias` at **5.0**. That used to be outside the −1…1 we chose for its slider
        // — this file is what caught it — so the range is now −10…10 (see `DevelopControl.range`),
        // wide enough to hold this camera's seed with headroom on both sides rather than at the edge.

        // Assert the *shape* rather than the exact numbers — a macOS update may retune a decoder
        // default, and that should not fail the suite. What must hold is that a supported knob's
        // seed is the decoder's own, not a constant we invented.
        XCTAssertTrue(caps.isSharpnessSupported, "the pinning below assumes this decoder sharpens")
        XCTAssertGreaterThan(
            caps.sharpnessAmount, 0,
            "this decoder sharpens by default; a 0 here means the probe is not reading the filter"
        )
        XCTAssertNotEqual(
            caps.sharpnessAmount, caps.sharpnessAmount.rounded(),
            "the sharpening seed should be a computed per-image value, not a round constant — that "
            + "is the whole reason it cannot be hardcoded"
        )
        XCTAssertGreaterThan(caps.colorNoiseReductionAmount, 0)
        XCTAssertGreaterThan(caps.baselineExposure, 0)

        // `lensCorrectionEnabled` is a `Bool`, so unlike the numeric seeds above it cannot be pinned
        // by "not zero, not round" — `false` is just as legitimate a decoder answer as `true`. It was
        // printed above but never asserted, which is exactly the gap `FakeRenderEngine.distinctivelySeeded`'s
        // doc comment warns about: a getter that dropped this seed and fell back to a hardcoded
        // constant would pass every existing check. This Leica reports it `true` — assert that, so a
        // regression back to a constant (in either direction) has something real to fail against.
        XCTAssertTrue(caps.lensCorrectionEnabled,
                      "this decoder enables lens correction by default; false here means the probe "
                      + "stopped reading lensCorrectionEnabled off the filter")

        // Which seeds land outside the slider that will display them. Written as a set rather than
        // a per-row assertion so the *membership* is the contract: a control joining or leaving this
        // list is a real change in what the panel does on open, and should be a deliberate edit to
        // `DevelopControl.range` and its doc comment, not a silent drift.
        //
        // This used to assert the set was exactly `{.shadowBias}` — encoding the pinned-slider defect
        // as the expected outcome. Now that `DevelopControl.range` has been widened to actually hold
        // this decoder's seeds (see its doc comment), the set should be empty; any control appearing
        // here is a new bug, not a known one. `testEveryPerImageSeedLandsStrictlyInsideItsSliderRange`
        // below is the sharper version of this same check — "inside" is not enough, it must not sit at
        // an edge either — but this one stays as the plain, cheap sanity check.
        let seeds: [(DevelopControl, Double)] = [
            (.baselineExposure, caps.baselineExposure),
            (.shadowBias, caps.shadowBias),
            (.whiteBalance, caps.asShotTemperature),
            (.sharpness, caps.sharpnessAmount),
            (.contrast, caps.contrastAmount),
            (.detail, caps.detailAmount),
            (.moireReduction, caps.moireReductionAmount),
            (.localToneMap, caps.localToneMapAmount),
            (.luminanceNoiseReduction, caps.luminanceNoiseReductionAmount),
            (.colorNoiseReduction, caps.colorNoiseReductionAmount),
        ]
        let outOfRange = Set(
            seeds.filter { caps.supports($0.0) && !$0.0.range.contains($0.1) }.map(\.0)
        )
        XCTAssertEqual(
            outOfRange, [],
            "a supported control's seed landed outside the slider that displays it — that control "
            + "will open pinned at an edge. Widen its range in DevelopControl.range and update the "
            + "doc comment there in the same commit."
        )

        // An unsupported adjustment is never queried, so its seed stays at the struct's default —
        // and the control is withdrawn anyway, so nothing can display it.
        XCTAssertFalse(caps.isLocalToneMapSupported,
                       "expected this decoder to refuse local tone mapping — if it now supports it, "
                       + "find another gate to pin rather than deleting this assertion")
        XCTAssertEqual(caps.localToneMapAmount, 0,
                       "an unsupported adjustment must not be probed; its seed stays at the default")
        XCTAssertFalse(caps.availableControls.contains(.localToneMap))
    }

    /// The test that would have caught the `shadowBias` defect: not "is the seed somewhere in the
    /// range", but "is it strictly inside it" — a seed sitting exactly on an endpoint is a slider that
    /// opens pinned just as surely as one sitting outside the range altogether, and `.contains(_:)`
    /// alone cannot tell a comfortable seed from one balanced on the edge.
    ///
    /// **Scope: the seeds whose range is ours to widen, plus the two colorimetric seeds with no
    /// "off" state.** `baselineExposure` and `shadowBias` have UI-invented ranges (see
    /// `DevelopControl.range`'s doc comment) — a seed pinned at either edge is exactly the defect this
    /// commit fixes, and the fix is to widen the range. `asShotTemperature` / `asShotTint` (the
    /// `whiteBalance` control and the separate `tintRange`) are per-image seeds too, and unlike an
    /// "amount" dial neither has a meaningful "off" value at either end — a colour temperature or tint
    /// pinned at its documented bound is a real problem, not a rest state.
    ///
    /// **Exempted from the *lower*-bound check only: the seven gated 0…N "amount" controls**
    /// (`sharpness`, `contrast`, `detail`, `moireReduction`, `localToneMap`,
    /// `luminanceNoiseReduction`, `colorNoiseReduction`). Their ranges are `CIRAWFilter`-documented,
    /// not ours to move, and `0` is those knobs' legitimate "no enhancement applied" rest value — this
    /// DNG's own seeds land exactly there for `contrast`, `detail`, `moireReduction`, and
    /// `luminanceNoiseReduction` (see the printout in `testProbingARealRAWReportsItsDecodersSeeds`). A
    /// slider opening at the bottom of a documented 0…N range because the decoder applied no
    /// enhancement is normal — the same shape as a volume slider resting at 0 — and not the "our range
    /// is too narrow" defect this test exists to catch.
    ///
    /// That exemption stops at the lower bound, though. Excluding these seven wholesale would also
    /// drop their **upper** bound, and a decoder reporting, say, `sharpnessAmount == 1.0` or
    /// `detailAmount == 3.0` — this control's own documented maximum — would open the slider pinned at
    /// full strength, which is exactly the "opens pinned" defect this test exists to catch. So the
    /// seven below still get checked against their upper bound; only the lower-bound rest state is
    /// exempt for them.
    ///
    /// `exposure`, `boost`, `boostShadow`, and `extendedDynamicRange` are excluded entirely:
    /// `CIRAWFilter` documents fixed defaults for these, not per-image seeds, and `developValue(for:)`
    /// never reads a seed for any of them. The three toggle controls (`lensCorrection`,
    /// `gamutMapping`, `highlightRecovery`) are excluded as well — a `Bool` seed is carried as literal
    /// 0 or 1 through a `Binding<Double>`, and sitting at an endpoint is exactly correct for those, not
    /// a defect.
    ///
    /// Skips on CI, which has no DNG — read a green CI run as saying nothing about this.
    func testEveryPerImageSeedLandsStrictlyInsideItsSliderRange() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW; see Fixtures.localRAWURL and PHASE2_SPEC §8.9")
        }
        let engine = RenderEngine()
        let source = ImageSource(url: rawURL, nativeExtent: .zero)
        let probed = await engine.rawCapabilities(for: source)
        let caps = try XCTUnwrap(probed)

        /// A seed sitting on either endpoint is pinned exactly as a seed outside the range is —
        /// `ClosedRange.contains(_:)` alone would pass both.
        func isStrictlyInside(_ value: Double, _ range: ClosedRange<Double>) -> Bool {
            range.contains(value) && value != range.lowerBound && value != range.upperBound
        }
        /// The lower-bound-exempt version, for the seven "amount" controls: `0` is a legitimate rest
        /// state for them, but the maximum is not.
        func isBelowUpperBound(_ value: Double, _ range: ClosedRange<Double>) -> Bool {
            range.contains(value) && value != range.upperBound
        }

        let strictControls: [(DevelopControl, Double)] = [
            (.baselineExposure, caps.baselineExposure),
            (.shadowBias, caps.shadowBias),
            (.whiteBalance, caps.asShotTemperature),
        ]
        for (control, value) in strictControls {
            XCTAssertTrue(
                isStrictlyInside(value, control.range),
                "\(control.rawValue) seeds at \(value), which is at or outside the edge of its "
                + "\(control.range) slider range — that control will open pinned. Widen the range "
                + "for \(control.rawValue) so the decoder's own default sits comfortably inside it."
            )
        }
        XCTAssertTrue(
            isStrictlyInside(caps.asShotTint, DevelopControl.tintRange),
            "tint seeds at \(caps.asShotTint), which is at or outside the edge of its "
            + "\(DevelopControl.tintRange) slider range — that control will open pinned."
        )

        let amountControls: [DevelopControl] = [
            .sharpness, .contrast, .detail, .moireReduction, .localToneMap,
            .luminanceNoiseReduction, .colorNoiseReduction,
        ]
        let amountValues: [DevelopControl: Double] = [
            .sharpness: caps.sharpnessAmount,
            .contrast: caps.contrastAmount,
            .detail: caps.detailAmount,
            .moireReduction: caps.moireReductionAmount,
            .localToneMap: caps.localToneMapAmount,
            .luminanceNoiseReduction: caps.luminanceNoiseReductionAmount,
            .colorNoiseReduction: caps.colorNoiseReductionAmount,
        ]
        for control in amountControls {
            let value = try XCTUnwrap(amountValues[control])
            XCTAssertTrue(
                isBelowUpperBound(value, control.range),
                "\(control.rawValue) seeds at \(value), the maximum of its \(control.range) slider "
                + "range — that control would open pinned at full strength. Widen the range for "
                + "\(control.rawValue) so the decoder's own default sits below the maximum."
            )
        }

        // Everything not checked above must be a control this test deliberately has nothing to say
        // about — see the doc comment. A new per-image seed landing in `developValue(for:)` without a
        // row in `strictControls` or `amountControls` must show up here, not slip past silently, which
        // is the same "a new case must arrive with a row" guard `testEveryControlsSliderRangeIsPinned`
        // applies to slider ranges.
        let excluded: Set<DevelopControl> = [
            .exposure, .boost, .boostShadow, .extendedDynamicRange,
            .lensCorrection, .gamutMapping, .highlightRecovery,
        ]
        XCTAssertEqual(
            Set(strictControls.map(\.0)).union(amountControls),
            Set(DevelopControl.allCases).subtracting(excluded),
            "every DevelopControl must be covered by the strict-inside check, the below-maximum "
            + "check, or the exclusion list above, or a new per-image seed would ship with no bounds "
            + "check at all"
        )
    }

    // MARK: - "Read a seed only behind its gate", which leaves no runtime trace

    /// Each gated seed in `RenderEngine.rawCapabilities(for:)` must be read behind its own
    /// `is*Supported` flag.
    ///
    /// **This reads source text, and for the same reason `RenderStackTests` does.** The requirement
    /// is unobservable at runtime: `CIRAWFilter` answers an unsupported property with *something* —
    /// on the Leica in `realworldtest/`, `localToneMapAmount` reads 0.0 whether you check
    /// `isLocalToneMapSupported` first or not, so deleting the gate changes no value this suite can
    /// see. It was verified by trying: dropping the `isLocalToneMapSupported ?` from that line leaves
    /// every other test in this file green. Another camera, or another macOS build, may well answer
    /// something else — and then a control the panel *does* offer would seed off a knob the decoder
    /// does not implement. The only way to keep the gates is to look at them.
    ///
    /// Deliberately narrow: it checks that each seed's argument text names its flag, not what the
    /// expression does with it. A rewrite that keeps the flag but inverts the test would slip
    /// through — this is a guard against deletion, which is the failure that actually happens.
    func testEveryGatedSeedIsReadBehindItsOwnSupportedFlag() throws {
        let source = URL(fileURLWithPath: #filePath)          // Tests/LUTzyKitTests/…
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()                       // package root
            .appendingPathComponent("Sources/LUTzyKit/Models/RenderEngine.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        let signature = "func rawCapabilities(for source: ImageSource) -> RAWCapabilities? {"
        let start = try XCTUnwrap(text.range(of: signature),
                                  "could not find rawCapabilities(for:) — was it renamed?")
        let rest = text[start.upperBound...]
        let end = try XCTUnwrap(rest.range(of: "\n    }"), "could not find the end of the method")
        let body = String(rest[..<end.lowerBound])

        // Every argument label the call passes, in order, so a seed's own text can be sliced out
        // without depending on how the expression happens to be line-wrapped.
        let labels = [
            "isSharpnessSupported:", "isContrastSupported:", "isDetailSupported:",
            "isMoireReductionSupported:", "isLocalToneMapSupported:",
            "isLuminanceNoiseReductionSupported:", "isColorNoiseReductionSupported:",
            "isLensCorrectionSupported:", "isHighlightRecoverySupported:",
            "asShotTemperature:", "asShotTint:", "baselineExposure:", "shadowBias:",
            "sharpnessAmount:", "contrastAmount:", "detailAmount:", "moireReductionAmount:",
            "localToneMapAmount:", "luminanceNoiseReductionAmount:", "colorNoiseReductionAmount:",
            "lensCorrectionEnabled:",
        ]

        /// The text the call passes for `label`, up to the next argument.
        ///
        /// **Must fail, not fail open, when a *reorder* is what broke the search.** `lensCorrectionEnabled:`
        /// is genuinely the last label in `labels`, so for it alone there is no "next" label to find —
        /// `nextIndex` lands out of bounds, and the rest of `body` legitimately *is* its value, since
        /// nothing else follows it in the source. That case returns `String(after)` and must not fail.
        /// But when `label` has a real next neighbour in `labels` and that neighbour's text cannot be
        /// found *after* `label` in `body`, the only way that happens is the arguments no longer appear
        /// in the expected order — and the old code silently returned `String(after)` there too: the
        /// entire rest of the method body, containing every other flag's text. `passed.contains(flag)`
        /// against that string is true almost by construction, so the whole test would pass vacuously on
        /// exactly the reorder it exists to catch. This is the only check guarding that invariant, so
        /// that specific parse miss has to be loud.
        func argument(_ label: String) throws -> String {
            let labelRange = try XCTUnwrap(body.range(of: label), "\(label) is not passed at all")
            let after = body[labelRange.upperBound...]
            let currentIndex = try XCTUnwrap(labels.firstIndex(of: label),
                                             "\(label) is missing from the labels array")
            let nextIndex = currentIndex + 1
            guard nextIndex < labels.count else {
                // `label` is the last argument in the call — nothing follows it, so `after` is
                // legitimately its whole value.
                return String(after)
            }
            guard let nextRange = after.range(of: labels[nextIndex]) else {
                XCTFail(
                    "could not find \(labels[nextIndex]) anywhere after \(label) in the source — the "
                    + "parser lost track of where \(label)'s value ends, most likely because the "
                    + "arguments were reordered, so this test can no longer vouch for anything"
                )
                return String(after)
            }
            return String(after[..<nextRange.lowerBound])
        }

        let gated = [
            ("sharpnessAmount:", "isSharpnessSupported"),
            ("contrastAmount:", "isContrastSupported"),
            ("detailAmount:", "isDetailSupported"),
            ("moireReductionAmount:", "isMoireReductionSupported"),
            ("localToneMapAmount:", "isLocalToneMapSupported"),
            ("luminanceNoiseReductionAmount:", "isLuminanceNoiseReductionSupported"),
            ("colorNoiseReductionAmount:", "isColorNoiseReductionSupported"),
            ("lensCorrectionEnabled:", "isLensCorrectionSupported"),
        ]

        for (label, flag) in gated {
            let passed = try argument(label)
            XCTAssertTrue(
                passed.contains(flag),
                "\(label.dropLast()) is read without checking \(flag). Querying an adjustment the "
                + "decoder does not offer answers nothing, and the answer would seed a slider. "
                + "Passed: \(passed.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }

        // `outputImage` is the other half of this method's contract — ~25 ms versus ~183 ms, and
        // touching it would disturb the developed-source memo. Also invisible to a value assertion.
        XCTAssertFalse(body.contains("outputImage"),
                       "the capability probe must never read outputImage — see its doc comment")
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
