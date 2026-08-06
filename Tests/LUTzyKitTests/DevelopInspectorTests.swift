import XCTest
import CoreImage
@testable import LUTzyKit

/// Phase 2 Step 10a. The ship gate is "the inspector drives live re-render", which is a claim about
/// wiring, so most of this drives `FakeRenderEngine` and asserts on the requests it recorded.
@MainActor
final class DevelopInspectorTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func openStandardImage(_ viewModel: AppViewModel) async throws {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "shot.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
    }

    // MARK: - Probing

    func testCapabilitiesArePublishedAfterOpeningAnImage() async throws {
        // Not `.everythingSupported`: that value is also `FakeRenderEngine.stubbedCapabilities`'
        // own field default, so an `AppViewModel` that hardcoded `.everythingSupported` and never
        // called the engine would pass this test just as happily. This is the "wrote a value that
        // equals the default" weakness (docs/CODE_REVIEW.md §2) — use a distinctive value, with a
        // mixed set of flags and non-round seeds, so the test can only pass if the engine's answer
        // actually made it through.
        let distinctiveCapabilities = RAWCapabilities(
            isSharpnessSupported: true,
            isDetailSupported: true,
            isLocalToneMapSupported: false,
            asShotTemperature: 5842.2,
            asShotTint: 14.04
        )
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(distinctiveCapabilities)
        let viewModel = AppViewModel(engine: fake)
        XCTAssertNil(viewModel.rawCapabilities, "nothing open yet")

        try await openStandardImage(viewModel)
        try await waitUntil("capabilities to arrive") { viewModel.rawCapabilities != nil }

        XCTAssertEqual(viewModel.rawCapabilities, distinctiveCapabilities)
    }

    /// The probe costs ~25 ms. Paying that once per image is fine; paying it per render would put it
    /// on every frame of a slider drag.
    func testCapabilitiesAreProbedOncePerOpenAndNotPerRender() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities to arrive") { viewModel.rawCapabilities != nil }

        let afterOpen = await fake.capabilityProbeCount
        XCTAssertEqual(afterOpen, 1, "one open, one probe")

        // Several renders, no new image.
        viewModel.updateDocument { $0.rawDevelop.exposure = 0.5 }
        viewModel.updateDocument { $0.rawDevelop.exposure = 0.6 }
        viewModel.selectLUT(TestImages.warmLUT())
        try await Task.sleep(for: .milliseconds(200))

        let afterRenders = await fake.capabilityProbeCount
        XCTAssertEqual(afterRenders, 1, "rendering must never re-probe")
    }

    /// A standard image has no develop stage, so the panel must have nothing to offer.
    func testCapabilitiesAreClearedForAnImageWithNoDevelopStage() async throws {
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(nil)
        let viewModel = AppViewModel(engine: fake)

        try await openStandardImage(viewModel)
        try await Task.sleep(for: .milliseconds(200))

        // `nil` alone is also `AppViewModel.rawCapabilities`' pre-open default, so on its own this
        // assertion cannot tell "the engine was consulted and answered nil" apart from "the engine
        // was never consulted at all." Assert the probe count too, so the test can only pass if the
        // engine actually ran.
        let probeCount = await fake.capabilityProbeCount
        XCTAssertEqual(probeCount, 1, "the engine must still be consulted even with no develop stage")
        XCTAssertNil(viewModel.rawCapabilities)
    }

    // MARK: - Debounce

    /// A slider drag is many ticks. Rendering each one would be two full renders per tick, because
    /// a develop change also re-rasterizes the side-by-side baseline.
    func testADragIssuesFarFewerRendersThanTicks() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        let atRest = await fake.previewRequests.count

        // Twenty ticks in quick succession, as a drag produces.
        for step in 1...20 {
            viewModel.updateDocument(debounced: true) {
                $0.rawDevelop.exposure = Double(step) / 20.0
            }
        }
        // Let the debounce settle and the final render land.
        try await waitUntil("the settled render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 1.0 }
        }

        let issued = await fake.previewRequests.count - atRest
        XCTAssertLessThan(issued, 10, "20 ticks issued \(issued) renders — the debounce is not working")
        XCTAssertGreaterThan(issued, 0)
    }

    /// ...and the value the user let go on is the one that gets rendered. A debounce that dropped
    /// the *last* event would leave the screen showing a value the slider is not on.
    func testTheFinalValueOfADragIsTheOneRendered() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        for step in 1...10 {
            viewModel.updateDocument(debounced: true) { $0.rawDevelop.exposure = Double(step) }
        }

        try await waitUntil("the final value to render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 10.0 }
        }
        XCTAssertEqual(viewModel.document.rawDevelop.exposure, 10.0,
                       "the document must hold the released value immediately, debounce or not")
    }

    /// Discrete controls stay immediate — a checkbox that lagged 60 ms would feel broken.
    ///
    /// The discriminator here is **sequence, not elapsed time**. Waiting up to some deadline (the
    /// previous version of this test waited up to 1 s against a 60 ms debounce) would pass even if
    /// the immediate path were secretly rerouted through the debounce, since 1 s comfortably outlasts
    /// 60 ms either way. Instead: issue a debounced edit with one value, then immediately (no
    /// `await` in between) an undebounced edit with a *different* value, then spin on `Task.yield()`
    /// — scheduling turns, not wall-clock time — until the undebounced value's render shows up.
    /// Hundreds of yields still complete in a tiny fraction of 60 ms on any real scheduler, so this
    /// only succeeds if the undebounced edit truly skipped the debounce; if it were routed through
    /// the same 60 ms sleep, the loop exhausts and the render is never seen. At that moment, the
    /// debounced edit's own value must not have rendered on its own either — that would mean its
    /// timer fired (or was never cancelled) independently of the undebounced edit, which should
    /// never happen since every call — debounced or not — cancels the prior develop task.
    func testAnUndebouncedEditRendersWithoutWaiting() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        // Debounced first — on its own this renders only ~60 ms from now.
        viewModel.updateDocument(debounced: true) { $0.rawDevelop.exposure = 0.42 }
        // Immediately after, with no suspension in between: an undebounced edit, distinct value.
        viewModel.updateDocument { $0.rawDevelop.gamutMappingEnabled = false }

        var sawUndebounced = false
        for _ in 0..<1000 {
            sawUndebounced = await fake.previewRequests.contains {
                $0.document.rawDevelop.gamutMappingEnabled == false
            }
            if sawUndebounced { break }
            await Task.yield()
        }
        XCTAssertTrue(sawUndebounced, "the undebounced edit must render without waiting for the debounce")

        // The debounced edit's value must never have rendered by itself (i.e. before the undebounced
        // edit's mutation had also landed) — it should have been pre-empted, not raced.
        let requestsSoFar = await fake.previewRequests
        XCTAssertFalse(
            requestsSoFar.contains {
                $0.document.rawDevelop.exposure == 0.42 && $0.document.rawDevelop.gamutMappingEnabled != false
            },
            "the debounced edit's own timer must not have fired independently"
        )
    }

    // MARK: - Coalesced bursts

    /// **Finding 1 regression.** A coalesced burst shares one `developTask`; only the last call's
    /// task survives to fire. Before the fix, `developChanged` was captured per call, so a burst
    /// that changed `rawDevelop` first and something else (here, `adjustments`) last would fire with
    /// the *last* call's `developChanged == false` — the comparison baseline would never re-render,
    /// leaving the side-by-side panel showing stale, pre-edit pixels indefinitely.
    func testAMixedBurstStillRendersTheComparisonBaseline() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        // First call in the burst changes rawDevelop...
        viewModel.updateDocument(debounced: true) { $0.rawDevelop.exposure = 0.8 }
        // ...a second call within the debounce window changes only adjustments. No `await` in
        // between, so both land before either's debounce timer has any chance to fire — exactly
        // what a coalesced burst of slider ticks produces.
        viewModel.updateDocument(debounced: true) { $0.adjustments = [.exposure(ev: 0.3)] }

        let expectedBaseline = viewModel.document.originalForComparison

        try await waitUntil("the comparison baseline to re-render") {
            await fake.previewRequests.contains { $0.document == expectedBaseline && $0.lutID == nil }
        }
    }

    // MARK: - The histogram belongs to the Info tab

    /// The histogram is gated on the inspector being open "so we don't tally pixels for a panel
    /// nobody's looking at" — its own words. The Develop tab breaks that: the inspector is open, the
    /// histogram is not on screen, and every settled render of a slider drag was tallying one. An
    /// open inspector parked on Develop is as much a panel nobody's looking at as a closed one.
    func testNoHistogramIsTalliedWhileTheDevelopTabIsShowing() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        // Switch first, *then* open: opening with Info showing would legitimately tally one.
        viewModel.inspectorTab = .develop
        viewModel.isInspectorPresented = true

        viewModel.developBinding(for: .exposure).wrappedValue = 0.9
        try await waitUntil("the develop render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 0.9 }
        }
        // The tally would be issued from the same task that publishes the preview, so by the time
        // that render is visible it would already be recorded. The sleep is belt and braces.
        try await Task.sleep(for: .milliseconds(150))

        let requests = await fake.histogramRequests
        XCTAssertTrue(requests.isEmpty,
                      "the Develop tab has no histogram; \(requests.count) tallies were issued for a "
                      + "chart nobody can see")
        XCTAssertNil(viewModel.histogram)
    }

    /// ...and coming **back** has to recompute, or the gate above just makes the histogram blank (on
    /// a first visit) or stale (on a return) for anyone who touched Develop.
    func testSwitchingBackToInfoRecomputesTheHistogram() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        viewModel.inspectorTab = .develop
        viewModel.isInspectorPresented = true

        // Edit while the histogram is off-screen. Nothing is tallied, so whatever Info shows next
        // can only be right if the switch itself recomputes.
        viewModel.developBinding(for: .exposure).wrappedValue = 0.9
        try await waitUntil("the develop render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 0.9 }
        }
        try await Task.sleep(for: .milliseconds(150))
        let beforeSwitch = await fake.histogramRequests
        XCTAssertTrue(beforeSwitch.isEmpty, "precondition: nothing tallied while on Develop")

        viewModel.inspectorTab = .info

        try await waitUntil("the histogram to be published") { viewModel.histogram != nil }
        let after = await fake.histogramRequests
        XCTAssertEqual(after.count, 1, "returning to Info should tally exactly once")
        XCTAssertEqual(
            after.first?.document.rawDevelop.exposure, 0.9,
            "the recomputed histogram must describe the document as it is now, not as it was when "
            + "the user left the tab"
        )
    }

    /// Leaving Info for Develop and coming back must not need an intervening render — and must not
    /// tally on the way *out*, either.
    func testLeavingInfoStopsTalliesAndReturningResumesThem() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        viewModel.isInspectorPresented = true   // Info is the default tab
        try await waitUntil("the first tally") { await !fake.histogramRequests.isEmpty }
        let onInfo = await fake.histogramRequests.count

        viewModel.inspectorTab = .develop
        try await Task.sleep(for: .milliseconds(100))
        let afterLeaving = await fake.histogramRequests.count
        XCTAssertEqual(afterLeaving, onInfo, "switching away must not tally")

        viewModel.inspectorTab = .info
        try await waitUntil("the tally on return") {
            await fake.histogramRequests.count > onInfo
        }
    }

    // MARK: - The ship gate: edits reach the renderer

    func testADevelopEditRendersTheChangedDocument() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        viewModel.developBinding(for: .exposure).wrappedValue = 1.25

        try await waitUntil("the edited render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 1.25 }
        }
    }

    /// A control bound to a `nil` setting has to show the decoder's own value, not zero. As-shot
    /// white balance on a real file is ~5842 K; a slider opening at 0 K would be nonsense.
    func testAnUnsetControlReadsBackTheSeedRatherThanZero() async throws {
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(RAWCapabilities(asShotTemperature: 5842.2, asShotTint: 14.04))
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        XCTAssertNil(viewModel.document.rawDevelop.neutralTemperature, "nothing written yet")
        XCTAssertEqual(viewModel.developBinding(for: .whiteBalance).wrappedValue, 5842.2, accuracy: 0.01,
                       "an unset white balance must display the file's as-shot value")
        XCTAssertEqual(viewModel.developBinding(for: .exposure).wrappedValue, 0,
                       "exposure has a fixed decoder default of 0")
    }

    /// Presenting the panel must not write anything. `.neutral` is byte-identical to
    /// `developRAWNeutral` *because it sets nothing*; seeding every field on open would quietly end
    /// that, and the derive baseline reasons about a neutral document.
    func testReadingEveryControlWritesNothing() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        for control in DevelopControl.allCases {
            _ = viewModel.developBinding(for: control).wrappedValue
        }

        XCTAssertTrue(viewModel.document.rawDevelop.isNeutral,
                      "opening the panel must not write settings")
    }

    /// **Every** seeded control reads **its own** seed.
    ///
    /// The previous version of this file proved the seed path for exactly one control, white
    /// balance, and every stub left the other seeds at 0 — so for the rest, "read the seed" and
    /// "return a hardcoded 0" were the same number and eight controls were guessing. A table with a
    /// distinct value per field means a getter reading the wrong seed names itself in the failure.
    func testEverySeededControlReadsItsOwnSeed() async throws {
        let caps = RAWCapabilities.distinctivelySeeded
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(caps)
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        let seeded: [(DevelopControl, Double)] = [
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
            (.lensCorrection, caps.lensCorrectionEnabled ? 1 : 0),
        ]

        // Distinctness is what gives the table its power: two rows sharing a value would let a
        // getter read the wrong field and still pass.
        XCTAssertEqual(Set(seeded.map(\.1)).count, seeded.count,
                       "the seed values must all differ, or a mis-wired getter can pass by accident")

        for (control, expected) in seeded {
            XCTAssertEqual(
                viewModel.developValue(for: control), expected, accuracy: 0.0001,
                "\(control.rawValue) must display the decoder's own seed, not a guessed constant"
            )
        }

        // Tint travels on its own binding, so it needs its own row.
        XCTAssertEqual(viewModel.developTintBinding().wrappedValue, caps.asShotTint, accuracy: 0.0001)

        // And the controls that genuinely *do* have a fixed documented default keep it — a blanket
        // "read a seed for everything" would have broken these.
        XCTAssertEqual(viewModel.developValue(for: .exposure), 0)
        XCTAssertEqual(viewModel.developValue(for: .boost), 1)
        XCTAssertEqual(viewModel.developValue(for: .boostShadow), 1)
        XCTAssertEqual(viewModel.developValue(for: .extendedDynamicRange), 0)
        XCTAssertEqual(viewModel.developValue(for: .gamutMapping), 1)
        XCTAssertEqual(viewModel.developValue(for: .highlightRecovery), 1)

        // Reading all of that still wrote nothing.
        XCTAssertTrue(viewModel.document.rawDevelop.isNeutral)
    }

    // MARK: - Tint

    /// Tint is the one control with no `DevelopControl` case of its own, so nothing in the table
    /// tests reaches it. It gets the same two guarantees as the rest: reading never writes, and what
    /// you set is what you read back.
    func testTheTintBindingRoundTripsAndNeverWritesOnRead() async throws {
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(RAWCapabilities(asShotTemperature: 5842.2, asShotTint: 14.04))
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        // Read, repeatedly. `.neutral` is byte-identical to `developRAWNeutral` *because it sets
        // nothing*; a getter that seeded on read would quietly end that and move the derive baseline.
        for _ in 0..<3 {
            XCTAssertEqual(viewModel.developTintBinding().wrappedValue, 14.04, accuracy: 0.0001,
                           "an unset tint must display the file's as-shot value")
        }
        XCTAssertNil(viewModel.document.rawDevelop.neutralTint, "reading must not write")
        XCTAssertTrue(viewModel.document.rawDevelop.isNeutral)

        // Write, then read back — through the binding, not the document, so a getter that ignored
        // the stored value and always returned the seed fails here.
        viewModel.developTintBinding().wrappedValue = -87.5
        XCTAssertEqual(viewModel.document.rawDevelop.neutralTint, -87.5)
        XCTAssertEqual(viewModel.developTintBinding().wrappedValue, -87.5, accuracy: 0.0001,
                       "a written tint must win over the seed")

        // And the write reaches the renderer.
        try await waitUntil("the tinted render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.neutralTint == -87.5 }
        }
    }

    // MARK: - Toggles take the immediate path

    /// `developBinding` passes `debounced: !control.isToggle`. Nothing exercised the `false` side of
    /// that expression, so a regression to always-debounce — dropping the negation, or the whole
    /// argument — would have gone green while every checkbox in the panel picked up a 60 ms lag.
    ///
    /// Same discriminator as `testAnUndebouncedEditRendersWithoutWaiting`: **sequence, not elapsed
    /// time**. A slider write goes first with a distinct value, then, with no suspension in between,
    /// a toggle write through the same binding. Spinning on `Task.yield()` — scheduling turns, not
    /// wall-clock — hundreds of times still costs a tiny fraction of the 60 ms debounce, so the
    /// toggle's render can only appear if it truly skipped the timer. If the toggle were routed
    /// through the debounce, the loop exhausts and the render never shows.
    func testWritingAToggleThroughTheBindingSkipsTheDebounce() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        // A slider control first — this one *should* wait ~60 ms.
        viewModel.developBinding(for: .exposure).wrappedValue = 0.42
        // ...and immediately a toggle, through the same binding factory.
        XCTAssertTrue(DevelopControl.gamutMapping.isToggle, "this test needs a toggle control")
        viewModel.developBinding(for: .gamutMapping).wrappedValue = 0

        var sawToggle = false
        for _ in 0..<1000 {
            sawToggle = await fake.previewRequests.contains {
                $0.document.rawDevelop.gamutMappingEnabled == false
            }
            if sawToggle { break }
            await Task.yield()
        }
        XCTAssertTrue(
            sawToggle,
            "a toggle written through developBinding must render immediately — developBinding is "
            + "passing debounced: true for a Bool control"
        )

        // The toggle's 0 must have become `false`, not 0.0 in some numeric field.
        XCTAssertEqual(viewModel.document.rawDevelop.gamutMappingEnabled, false)
        // And the slider's debounced edit must not have fired on its own timer in the meantime.
        let soFar = await fake.previewRequests
        XCTAssertFalse(
            soFar.contains {
                $0.document.rawDevelop.exposure == 0.42
                    && $0.document.rawDevelop.gamutMappingEnabled != false
            },
            "the slider's debounce should have been pre-empted, not raced"
        )
    }

    /// The mirror image: a *slider* written through the same binding must still be debounced, or the
    /// test above could be satisfied by making everything immediate.
    func testWritingASliderThroughTheBindingStillDebounces() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        let atRest = await fake.previewRequests.count

        XCTAssertFalse(DevelopControl.exposure.isToggle)
        for step in 1...20 {
            viewModel.developBinding(for: .exposure).wrappedValue = Double(step) / 20.0
        }
        try await waitUntil("the settled render") {
            await fake.previewRequests.contains { $0.document.rawDevelop.exposure == 1.0 }
        }

        let issued = await fake.previewRequests.count - atRest
        XCTAssertLessThan(issued, 10,
                          "20 slider ticks issued \(issued) renders — developBinding stopped debouncing")
    }

    func testResettingAControlReturnsItToUnset() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities") { viewModel.rawCapabilities != nil }

        viewModel.developBinding(for: .exposure).wrappedValue = 2.0
        XCTAssertEqual(viewModel.document.rawDevelop.exposure, 2.0)

        viewModel.resetDevelop(.exposure)
        XCTAssertNil(viewModel.document.rawDevelop.exposure, "reset means unset, not zero")

        viewModel.developBinding(for: .exposure).wrappedValue = 2.0
        viewModel.developBinding(for: .whiteBalance).wrappedValue = 3000
        viewModel.resetAllDevelop()
        XCTAssertTrue(viewModel.document.rawDevelop.isNeutral)
    }
}
