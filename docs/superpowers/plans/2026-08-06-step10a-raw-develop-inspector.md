# Phase 2 Step 10a — RAW Develop Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a RAW develop panel in the `⌘I` inspector whose controls are gated per-image on the real `CIRAWFilter` `is*Supported` flags, and whose edits drive a live, debounced re-render.

**Architecture:** The `is*Supported` flags live on `CIRAWFilter`, which is non-`Sendable` and confined to `actor RenderEngine`. A new `RAWCapabilities` value carries them — plus the per-image seed values a slider needs when a setting is `nil` — across the actor boundary, probed once per image open. The panel is a `ForEach` over a pure `availableControls` array so the gating is testable without SwiftUI view tests.

**Tech Stack:** Swift 6 language mode, SwiftUI, Core Image (`CIRAWFilter`), XCTest. Apple frameworks only.

## Global Constraints

- **macOS 14 deployment target**; CI builds on `macos-26` with the macOS 26 SDK. Newer API goes behind `#available`, never avoided. Xcode 26+ required to build.
- **Zero third-party dependencies.** Apple frameworks only. No SPM/CocoaPods/Carthage.
- **Swift 6 language mode with zero escape hatches.** No `@unchecked Sendable`, no `nonisolated(unsafe)`, no `@preconcurrency`. `PackageSettingsTests` fails if any appear. No mutable global state.
- **Ship gate:** `swift build` → `swift test` → `swift build -c release`, all clean with **no warnings**.
- **Keep the module surface internal.** Only `ContentView` and `LUTzyCommands` are `public`. Widening `private` → internal for a test requires a comment saying why.
- **Branch + PR, never straight to `main`.** Commit messages end with the `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` trailer.
- **`CIImage`/`CIFilter`/`CIContext`/`CIRAWFilter` must stay inside `RenderEngine`.** Only `Sendable` values cross out.
- Work happens on branch `feature/phase2-develop-inspector`, already created off `main`, already holding the design doc at `7c0934f`.
- Tests needing a RAW use `Fixtures.localRAWURL` and **must `XCTSkip`** when it is `nil`. CI never has a DNG.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/LUTzyKit/Models/RAWCapabilities.swift` | **new.** The `Sendable` value: nine support flags, four per-image seeds, and the pure `availableControls` list. Also `DevelopControl`, the enum naming one knob. |
| `Sources/LUTzyKit/Models/RenderEngine.swift` | **modify.** `rawCapabilities(for:)` on the `RenderEngining` protocol and on the actor. |
| `Sources/LUTzyKit/ViewModels/AppViewModel.swift` | **modify.** Published capabilities, probe on open, debounced develop edits. |
| `Sources/LUTzyKit/Views/DevelopInspectorView.swift` | **new.** The panel: a `ForEach` over `availableControls`. |
| `Sources/LUTzyKit/Views/InfoInspectorView.swift` | **modify.** Segmented Info/Develop container at the top. |
| `Tests/LUTzyKitTests/RAWCapabilitiesTests.swift` | **new.** `availableControls` gating, seeds, real-RAW probe. |
| `Tests/LUTzyKitTests/DevelopInspectorTests.swift` | **new.** Live re-render, debounce, non-RAW inertness, probe-once. |
| `Tests/LUTzyKitTests/FakeRenderEngine.swift` | **modify.** Conform to the new protocol method; record probe calls. |
| `scripts/mutate-step10a.sh` | **new.** Mutation harness. |
| `docs/CODE_REVIEW.md`, `docs/PHASE2_SPEC.md` | **modify.** Correct the §5 untestable-gates claim; split the §6 row. |

---

## Task 1: `RAWCapabilities` and `DevelopControl`

**Files:**
- Create: `Sources/LUTzyKit/Models/RAWCapabilities.swift`
- Test: `Tests/LUTzyKitTests/RAWCapabilitiesTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct RAWCapabilities: Sendable, Equatable` with stored properties `isSharpnessSupported`, `isContrastSupported`, `isDetailSupported`, `isMoireReductionSupported`, `isLocalToneMapSupported`, `isLuminanceNoiseReductionSupported`, `isColorNoiseReductionSupported`, `isLensCorrectionSupported`, `isHighlightRecoverySupported` (all `Bool`), and `asShotTemperature`, `asShotTint`, `baselineExposure`, `shadowBias` (all `Double`); a memberwise `init` with every flag defaulting to `false` and every seed to `0`; `static let everythingSupported: RAWCapabilities`; `var availableControls: [DevelopControl]`. Plus `enum DevelopControl: String, Sendable, CaseIterable` with cases `exposure`, `baselineExposure`, `shadowBias`, `boost`, `boostShadow`, `whiteBalance`, `sharpness`, `contrast`, `detail`, `moireReduction`, `localToneMap`, `luminanceNoiseReduction`, `colorNoiseReduction`, `lensCorrection`, `gamutMapping`, `extendedDynamicRange`, `highlightRecovery`, and `var title: String`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LUTzyKitTests/RAWCapabilitiesTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RAWCapabilitiesTests`
Expected: FAIL to compile — `cannot find 'RAWCapabilities' in scope`. That is the expected failure for this step; a missing type cannot fail any other way.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/LUTzyKit/Models/RAWCapabilities.swift`:

```swift
import Foundation

/// One knob in the develop panel.
///
/// A value rather than a set of `if`s in a `ViewBuilder`, so which controls a given file offers can
/// be asserted without instantiating a view — this repo has no SwiftUI view tests. The declaration
/// order below **is** the panel's layout order.
enum DevelopControl: String, Sendable, CaseIterable {
    case exposure
    case baselineExposure
    case shadowBias
    case boost
    case boostShadow
    case whiteBalance
    case sharpness
    case contrast
    case detail
    case moireReduction
    case localToneMap
    case luminanceNoiseReduction
    case colorNoiseReduction
    case lensCorrection
    case gamutMapping
    case extendedDynamicRange
    case highlightRecovery

    var title: String {
        switch self {
        case .exposure: return "Exposure"
        case .baselineExposure: return "Baseline Exposure"
        case .shadowBias: return "Shadow Bias"
        case .boost: return "Boost"
        case .boostShadow: return "Boost Shadows"
        case .whiteBalance: return "White Balance"
        case .sharpness: return "Sharpness"
        case .contrast: return "Local Contrast"
        case .detail: return "Detail"
        case .moireReduction: return "Moiré Reduction"
        case .localToneMap: return "Local Tone Map"
        case .luminanceNoiseReduction: return "Luminance NR"
        case .colorNoiseReduction: return "Colour NR"
        case .lensCorrection: return "Lens Correction"
        case .gamutMapping: return "Gamut Mapping"
        case .extendedDynamicRange: return "Extended Dynamic Range"
        case .highlightRecovery: return "Highlight Recovery"
        }
    }
}

/// What one particular RAW file's decoder can do, and where its own defaults sit.
///
/// **Why this type exists.** `CIRAWFilter` exposes an `is*Supported` flag per adjustment, and writing
/// to an unsupported one is at best ignored — `RAWDevelopSettings.apply(to:)` already honours that.
/// But `CIRAWFilter` is not `Sendable` and lives inside `actor RenderEngine` (`PHASE2_SPEC.md` §4.5),
/// so a `@MainActor` inspector cannot read those flags. This is the value that crosses the boundary.
///
/// **It carries seeds as well as flags, and that is not padding.** Every `RAWDevelopSettings`
/// property is `Optional` with `nil` meaning "leave the decoder at its default", and several of those
/// defaults *vary per image* — as-shot white balance on the Leica in `realworldtest/` is
/// 5842.2 K / 14.04, not a round number. A slider bound to a `nil` setting has nothing to display
/// without these.
struct RAWCapabilities: Sendable, Equatable {

    // MARK: - Gates

    var isSharpnessSupported: Bool
    var isContrastSupported: Bool
    var isDetailSupported: Bool
    var isMoireReductionSupported: Bool
    var isLocalToneMapSupported: Bool
    var isLuminanceNoiseReductionSupported: Bool
    var isColorNoiseReductionSupported: Bool
    var isLensCorrectionSupported: Bool
    /// Always false below macOS 26, where the property is not in the imported interface at all.
    var isHighlightRecoverySupported: Bool

    // MARK: - Per-image seeds

    var asShotTemperature: Double
    var asShotTint: Double
    var baselineExposure: Double
    var shadowBias: Double

    init(
        isSharpnessSupported: Bool = false,
        isContrastSupported: Bool = false,
        isDetailSupported: Bool = false,
        isMoireReductionSupported: Bool = false,
        isLocalToneMapSupported: Bool = false,
        isLuminanceNoiseReductionSupported: Bool = false,
        isColorNoiseReductionSupported: Bool = false,
        isLensCorrectionSupported: Bool = false,
        isHighlightRecoverySupported: Bool = false,
        asShotTemperature: Double = 0,
        asShotTint: Double = 0,
        baselineExposure: Double = 0,
        shadowBias: Double = 0
    ) {
        self.isSharpnessSupported = isSharpnessSupported
        self.isContrastSupported = isContrastSupported
        self.isDetailSupported = isDetailSupported
        self.isMoireReductionSupported = isMoireReductionSupported
        self.isLocalToneMapSupported = isLocalToneMapSupported
        self.isLuminanceNoiseReductionSupported = isLuminanceNoiseReductionSupported
        self.isColorNoiseReductionSupported = isColorNoiseReductionSupported
        self.isLensCorrectionSupported = isLensCorrectionSupported
        self.isHighlightRecoverySupported = isHighlightRecoverySupported
        self.asShotTemperature = asShotTemperature
        self.asShotTint = asShotTint
        self.baselineExposure = baselineExposure
        self.shadowBias = shadowBias
    }

    /// A decoder that refuses nothing. For tests, and for reasoning about the upper bound.
    static let everythingSupported = RAWCapabilities(
        isSharpnessSupported: true,
        isContrastSupported: true,
        isDetailSupported: true,
        isMoireReductionSupported: true,
        isLocalToneMapSupported: true,
        isLuminanceNoiseReductionSupported: true,
        isColorNoiseReductionSupported: true,
        isLensCorrectionSupported: true,
        isHighlightRecoverySupported: true
    )

    /// Whether this file's decoder offers `control`.
    func supports(_ control: DevelopControl) -> Bool {
        switch control {
        case .exposure, .baselineExposure, .shadowBias, .boost, .boostShadow,
             .whiteBalance, .gamutMapping, .extendedDynamicRange:
            // Ungated: `RAWDevelopSettings.apply(to:)` writes these for every decodable RAW.
            return true
        case .sharpness: return isSharpnessSupported
        case .contrast: return isContrastSupported
        case .detail: return isDetailSupported
        case .moireReduction: return isMoireReductionSupported
        case .localToneMap: return isLocalToneMapSupported
        case .luminanceNoiseReduction: return isLuminanceNoiseReductionSupported
        case .colorNoiseReduction: return isColorNoiseReductionSupported
        case .lensCorrection: return isLensCorrectionSupported
        case .highlightRecovery: return isHighlightRecoverySupported
        }
    }

    /// The controls to draw, in panel order.
    ///
    /// An unsupported control is **omitted, not disabled**: a greyed-out slider invites the user to
    /// wonder what they did wrong, where absence reads correctly as "this camera's decoder does not
    /// do that".
    var availableControls: [DevelopControl] {
        DevelopControl.allCases.filter(supports)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RAWCapabilitiesTests`
Expected: PASS — `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/LUTzyKit/Models/RAWCapabilities.swift Tests/LUTzyKitTests/RAWCapabilitiesTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10a: RAWCapabilities and DevelopControl

The is*Supported flags live on a non-Sendable CIRAWFilter inside the render
actor, so a @MainActor inspector cannot read them. This is the value that
crosses the boundary.

availableControls is a pure ordered array rather than a set of ifs in a
ViewBuilder, because the repo has no SwiftUI view tests: expressed as a value,
the ship gate's per-image gating is one assertion.

It carries per-image seeds as well as flags. Every RAWDevelopSettings property
is Optional with nil meaning "decoder default", and several defaults vary per
image, so a slider bound to nil has nothing to display without them.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Probe the capabilities inside the actor

**Files:**
- Modify: `Sources/LUTzyKit/Models/RenderEngine.swift` (add to the `RenderEngining` protocol, and to the actor)
- Modify: `Tests/LUTzyKitTests/FakeRenderEngine.swift`
- Test: `Tests/LUTzyKitTests/RAWCapabilitiesTests.swift` (append)

**Interfaces:**
- Consumes: `RAWCapabilities`, `DevelopControl` from Task 1.
- Produces: `func rawCapabilities(for source: ImageSource) async -> RAWCapabilities?` on `RenderEngining`, returning `nil` for a non-RAW source. On `FakeRenderEngine`: `private(set) var capabilityProbeCount: Int`, `var stubbedCapabilities: RAWCapabilities?`, and `func setStubbedCapabilities(_ value: RAWCapabilities?)`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/LUTzyKitTests/RAWCapabilitiesTests.swift`, inside the class:

```swift
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

        let caps = try XCTUnwrap(await engine.rawCapabilities(for: source))

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RAWCapabilitiesTests`
Expected: FAIL to compile — `value of type 'RenderEngine' has no member 'rawCapabilities'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/LUTzyKit/Models/RenderEngine.swift`, append to the `RenderEngining` protocol, immediately after the `invalidateLUTCache()` declaration:

```swift
    /// What this source's RAW decoder can do, and where its own defaults sit. `nil` for a non-RAW.
    ///
    /// On the protocol because the develop inspector needs it and cannot reach a `CIRAWFilter`:
    /// the flags live on a non-`Sendable` type confined to the actor (§4.5). Returning a value is
    /// the only way the panel can be gated on what the decoder actually supports.
    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities?
```

Then add to `actor RenderEngine`, immediately before the `// MARK: - Cache` section:

```swift
    // MARK: - RAW capabilities

    /// Build a throwaway `CIRAWFilter` and read its flags and its own defaults.
    ///
    /// **`outputImage` is deliberately never touched.** That is the difference between ~25 ms and
    /// ~183 ms on a 30 MB DNG (measured; see the Step 10a design doc), and it is why this can run on
    /// every image open without being felt. It also leaves the developed-source memo alone — a
    /// capability question must not evict the image the user is looking at.
    func rawCapabilities(for source: ImageSource) -> RAWCapabilities? {
        guard case .raw = source.kind else { return nil }
        guard let filter = RenderPipeline.rawFilter(for: source.backing) else { return nil }

        var highlightRecovery = false
        if #available(macOS 26, *) {
            highlightRecovery = filter.isHighlightRecoverySupported
        }

        return RAWCapabilities(
            isSharpnessSupported: filter.isSharpnessSupported,
            isContrastSupported: filter.isContrastSupported,
            isDetailSupported: filter.isDetailSupported,
            isMoireReductionSupported: filter.isMoireReductionSupported,
            isLocalToneMapSupported: filter.isLocalToneMapSupported,
            isLuminanceNoiseReductionSupported: filter.isLuminanceNoiseReductionSupported,
            isColorNoiseReductionSupported: filter.isColorNoiseReductionSupported,
            isLensCorrectionSupported: filter.isLensCorrectionSupported,
            isHighlightRecoverySupported: highlightRecovery,
            asShotTemperature: Double(filter.neutralTemperature),
            asShotTint: Double(filter.neutralTint),
            baselineExposure: Double(filter.baselineExposure),
            shadowBias: Double(filter.shadowBias)
        )
    }
```

`RenderPipeline.rawFilter(for:)` is currently `private static`. Change its declaration in `Sources/LUTzyKit/Models/RenderPipeline.swift` from:

```swift
    private static func rawFilter(for backing: ImageSource.Backing) -> CIRAWFilter? {
```

to:

```swift
    /// Internal rather than private since Step 10a: `RenderEngine.rawCapabilities` builds a filter
    /// purely to read its `is*Supported` flags, and duplicating the two-case construction would be
    /// two places for the `identifierHint` decision to drift.
    static func rawFilter(for backing: ImageSource.Backing) -> CIRAWFilter? {
```

The call in `RenderEngine.rawCapabilities` above is already written as `RenderPipeline.rawFilter(for: source.backing)` — `RenderEngine` and `RenderPipeline` are different types, so `Self.` would not resolve.

In `Tests/LUTzyKitTests/FakeRenderEngine.swift`, add before `func setShouldFailEncode(_ value: Bool)`:

```swift
    /// How many times the app asked for capabilities. The probe costs ~25 ms, so "once per image
    /// open" is a requirement, not a detail — a count is the only way to see it.
    private(set) var capabilityProbeCount = 0

    /// What the fake reports. `nil` models a standard image.
    var stubbedCapabilities: RAWCapabilities? = .everythingSupported

    func rawCapabilities(for source: ImageSource) -> RAWCapabilities? {
        capabilityProbeCount += 1
        return stubbedCapabilities
    }

    func setStubbedCapabilities(_ value: RAWCapabilities?) { stubbedCapabilities = value }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RAWCapabilitiesTests`
Expected: PASS — `Executed 7 tests, with 0 failures` locally. On a machine with no DNG, `Executed 7 tests, with 1 test skipped`.

- [ ] **Step 5: Verify the whole suite still builds and passes**

Run: `swift test`
Expected: `0 failures`. `RenderStackTests.testOnlyTwoTypesInTheModuleOwnACIContext` must still pass — this task adds no `CIContext`.

- [ ] **Step 6: Commit**

```bash
git add Sources/LUTzyKit/Models/RenderEngine.swift Sources/LUTzyKit/Models/RenderPipeline.swift Tests/LUTzyKitTests/FakeRenderEngine.swift Tests/LUTzyKitTests/RAWCapabilitiesTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10a: probe RAW capabilities inside the actor

rawCapabilities(for:) builds a throwaway CIRAWFilter and reads its flags and
its own defaults, never touching outputImage — measured, that is ~25 ms against
~183 ms for a full develop, and it leaves the developed-source memo alone.

RenderPipeline.rawFilter widens from private to internal so the construction is
not duplicated; the identifierHint decision should live in one place.

The real-RAW test corrects CODE_REVIEW §5 in passing: isLocalToneMapSupported
is false on the Leica DNG, so the gated branch it called untestable is
coverable locally.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Probe once per image open, and publish it

**Files:**
- Modify: `Sources/LUTzyKit/ViewModels/AppViewModel.swift`
- Test: `Tests/LUTzyKitTests/DevelopInspectorTests.swift` (create)

**Interfaces:**
- Consumes: `RAWCapabilities`, `rawCapabilities(for:)` from Tasks 1–2; `FakeRenderEngine.capabilityProbeCount`, `.setStubbedCapabilities(_:)`.
- Produces: `AppViewModel.rawCapabilities: RAWCapabilities?` (published, `private(set)`).

- [ ] **Step 1: Write the failing test**

Create `Tests/LUTzyKitTests/DevelopInspectorTests.swift`:

```swift
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
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(.everythingSupported)
        let viewModel = AppViewModel(engine: fake)
        XCTAssertNil(viewModel.rawCapabilities, "nothing open yet")

        try await openStandardImage(viewModel)
        try await waitUntil("capabilities to arrive") { viewModel.rawCapabilities != nil }

        XCTAssertEqual(viewModel.rawCapabilities, .everythingSupported)
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

        XCTAssertNil(viewModel.rawCapabilities)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DevelopInspectorTests`
Expected: FAIL to compile — `value of type 'AppViewModel' has no member 'rawCapabilities'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/LUTzyKit/ViewModels/AppViewModel.swift`, add after the `imageSource` property declaration:

```swift
    /// What the open image's RAW decoder can do, and where its own defaults sit. `nil` for a
    /// standard image, which has no develop stage at all.
    ///
    /// Probed once per open rather than per render: the probe builds a `CIRAWFilter`, which measures
    /// ~25 ms on a 30 MB DNG. Not memoized across images — one entry would save that on returning to
    /// an image, at the cost of another cache whose invalidation nobody will remember.
    @Published private(set) var rawCapabilities: RAWCapabilities?

    private var capabilitiesTask: Task<Void, Never>?
```

In `load(name:url:data:)`, add `capabilitiesTask?.cancel()` to the cancellation block at the top, immediately after `intensityTask?.cancel()`:

```swift
        capabilitiesTask?.cancel()
```

Then in the same method, in the `case .success(let ci):` branch, immediately after the line `self.refreshMetadata(url: url, data: data)`, add:

```swift
                self.refreshCapabilities()
```

And add this method immediately after `refreshMetadata(url:data:)`:

```swift
    /// Ask the engine what this image's decoder supports.
    ///
    /// Runs alongside the preview render rather than in front of it: the panel can appear a frame
    /// late, but first pixels should not wait on a capability question.
    private func refreshCapabilities() {
        capabilitiesTask?.cancel()
        rawCapabilities = nil

        guard let imageSource else { return }
        capabilitiesTask = Task { [engine] in
            let capabilities = await engine.rawCapabilities(for: imageSource)
            guard !Task.isCancelled else { return }
            self.rawCapabilities = capabilities
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DevelopInspectorTests`
Expected: PASS — `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/LUTzyKit/ViewModels/AppViewModel.swift Tests/LUTzyKitTests/DevelopInspectorTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10a: probe capabilities once per image open

Published on AppViewModel, refreshed on open, cleared for a standard image.
The probe runs alongside the preview render rather than in front of it: the
panel can appear a frame late, but first pixels should not wait on a
capability question.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Debounced develop edits

**Files:**
- Modify: `Sources/LUTzyKit/ViewModels/AppViewModel.swift`
- Test: `Tests/LUTzyKitTests/DevelopInspectorTests.swift` (append)

**Interfaces:**
- Consumes: `AppViewModel.updateDocument(_:)` as it exists.
- Produces: `func updateDocument(debounced: Bool, _ transform: (inout EditDocument) -> Void)`. The existing `updateDocument(_:)` keeps its signature and behaviour and forwards with `debounced: false`.

- [ ] **Step 1: Write the failing test**

Append to `DevelopInspectorTests`:

```swift
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
    func testAnUndebouncedEditRendersWithoutWaiting() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        viewModel.updateDocument { $0.rawDevelop.gamutMappingEnabled = false }

        try await waitUntil("the immediate render", timeout: 1) {
            await fake.previewRequests.contains { $0.document.rawDevelop.gamutMappingEnabled == false }
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DevelopInspectorTests`
Expected: FAIL to compile — `extra argument 'debounced' in call`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/LUTzyKit/ViewModels/AppViewModel.swift`, add a stored property next to the other task handles:

```swift
    private var developTask: Task<Void, Never>?
```

Replace the body of `updateDocument(_ transform:)` — keeping its doc comment — so the file reads:

```swift
    func updateDocument(_ transform: (inout EditDocument) -> Void) {
        updateDocument(debounced: false, transform)
    }

    /// Mutate the document and re-render, optionally coalescing a burst of edits into one render.
    ///
    /// **`debounced: true` is for continuous controls only** — a slider drag, where the user
    /// produces tens of values per second and only the one they settle on matters. `PHASE2_SPEC.md`
    /// §6 is explicit that open and filmstrip navigation must stay immediate, and discrete controls
    /// (toggles, resets) should too: a checkbox that lagged 60 ms would feel broken.
    ///
    /// The document itself is updated **immediately** either way. Only the render is deferred, so
    /// the control stays glued to the pointer and `document` is always the truth. Deferring the
    /// document as well would mean a read-back mid-drag saw a stale value.
    ///
    /// Worth the machinery because a develop change costs *two* renders — `scheduleOriginalPreview`
    /// as well as `schedulePreview`, since the comparison baseline moves with develop.
    func updateDocument(debounced: Bool, _ transform: (inout EditDocument) -> Void) {
        var updated = document
        transform(&updated)
        guard updated != document else { return }

        let developChanged = updated.rawDevelop != document.rawDevelop
        document = updated

        guard debounced else {
            developTask?.cancel()
            if developChanged { scheduleOriginalPreview() }
            schedulePreview()
            return
        }

        developTask?.cancel()
        developTask = Task {
            try? await Task.sleep(for: .milliseconds(Self.intensityDebounceMs))
            guard !Task.isCancelled else { return }
            if developChanged { self.scheduleOriginalPreview() }
            self.schedulePreview()
        }
    }
```

Also add `developTask?.cancel()` to the cancellation block at the top of `load(name:url:data:)`, immediately after the `capabilitiesTask?.cancel()` line added in Task 3.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DevelopInspectorTests`
Expected: PASS — `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: `0 failures`. `PreviewCutoverTests` exercises `updateDocument(_:)` heavily and must be unaffected — the one-argument form still renders synchronously.

- [ ] **Step 6: Commit**

```bash
git add Sources/LUTzyKit/ViewModels/AppViewModel.swift Tests/LUTzyKitTests/DevelopInspectorTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10a: debounce continuous develop edits

updateDocument gains a debounced variant using the 60 ms the intensity slider
already uses. The document updates immediately either way — only the render is
deferred — so a control stays glued to the pointer and `document` is never
stale mid-drag.

Worth the machinery because a develop change costs two renders, not one: the
side-by-side baseline moves with develop, so scheduleOriginalPreview fires
alongside schedulePreview.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: The develop panel

**Files:**
- Create: `Sources/LUTzyKit/Views/DevelopInspectorView.swift`
- Modify: `Sources/LUTzyKit/Views/InfoInspectorView.swift`
- Test: `Tests/LUTzyKitTests/DevelopInspectorTests.swift` (append)

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: `struct DevelopInspectorView: View` taking `@ObservedObject var viewModel: AppViewModel`; `AppViewModel.inspectorTab: InspectorTab` (published, read-write) and `enum InspectorTab: String, CaseIterable { case info, develop }`; `AppViewModel.developBinding(for:)` returning a `Binding<Double>`; `AppViewModel.resetDevelop(_:)` and `AppViewModel.resetAllDevelop()`.

- [ ] **Step 1: Write the failing test**

Append to `DevelopInspectorTests`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DevelopInspectorTests`
Expected: FAIL to compile — `value of type 'AppViewModel' has no member 'developBinding'`.

- [ ] **Step 3: Write the view-model half**

In `Sources/LUTzyKit/ViewModels/AppViewModel.swift`, add near the other published UI state (next to `isInspectorPresented`):

```swift
    /// Which half of the inspector is showing.
    @Published var inspectorTab: InspectorTab = .info

    enum InspectorTab: String, CaseIterable, Sendable {
        case info, develop
        var title: String {
            switch self {
            case .info: return "Info"
            case .develop: return "Develop"
            }
        }
    }
```

Add a new `// MARK: - RAW develop` section immediately after `updateDocument(debounced:_:)`:

```swift
    // MARK: - RAW develop

    /// A two-way binding for one develop control.
    ///
    /// **Reading never writes.** Every `RAWDevelopSettings` property is `Optional`, with `nil`
    /// meaning "leave `CIRAWFilter` at its decoder default", and `.neutral` is byte-identical to
    /// `ImageDecoder.developRAWNeutral` precisely *because it sets nothing*. So the getter falls back
    /// to the decoder's own value — a fixed default where there is one, otherwise the per-image seed
    /// from `rawCapabilities` — and only the setter stores anything. Seeding every field when the
    /// panel opened would silently make every document non-neutral.
    ///
    /// Writes are debounced: these back sliders.
    func developBinding(for control: DevelopControl) -> Binding<Double> {
        Binding(
            get: { self.developValue(for: control) },
            set: { newValue in
                self.updateDocument(debounced: true) { document in
                    Self.setDevelop(control, to: newValue, in: &document.rawDevelop)
                }
            }
        )
    }

    /// What a control should display: the stored setting, else the decoder's own starting point.
    func developValue(for control: DevelopControl) -> Double {
        let develop = document.rawDevelop
        let seed = rawCapabilities
        switch control {
        case .exposure: return develop.exposure ?? 0
        case .baselineExposure: return develop.baselineExposure ?? seed?.baselineExposure ?? 0
        case .shadowBias: return develop.shadowBias ?? seed?.shadowBias ?? 0
        case .boost: return develop.boostAmount ?? 1
        case .boostShadow: return develop.boostShadowAmount ?? 1
        case .whiteBalance: return develop.neutralTemperature ?? seed?.asShotTemperature ?? 6500
        case .sharpness: return develop.sharpnessAmount ?? 0
        case .contrast: return develop.contrastAmount ?? 0
        case .detail: return develop.detailAmount ?? 0
        case .moireReduction: return develop.moireReductionAmount ?? 0
        case .localToneMap: return develop.localToneMapAmount ?? 0
        case .luminanceNoiseReduction: return develop.luminanceNoiseReductionAmount ?? 0
        case .colorNoiseReduction: return develop.colorNoiseReductionAmount ?? 0
        case .lensCorrection: return (develop.lensCorrectionEnabled ?? true) ? 1 : 0
        case .gamutMapping: return (develop.gamutMappingEnabled ?? true) ? 1 : 0
        case .extendedDynamicRange: return develop.extendedDynamicRangeAmount ?? 0
        case .highlightRecovery: return (develop.highlightRecoveryEnabled ?? true) ? 1 : 0
        }
    }

    /// The tint half of white balance. Separate because `whiteBalance` is one row with two sliders.
    func developTintBinding() -> Binding<Double> {
        Binding(
            get: { self.document.rawDevelop.neutralTint ?? self.rawCapabilities?.asShotTint ?? 0 },
            set: { newValue in
                self.updateDocument(debounced: true) { $0.rawDevelop.neutralTint = newValue }
            }
        )
    }

    private static func setDevelop(
        _ control: DevelopControl, to value: Double, in develop: inout RAWDevelopSettings
    ) {
        switch control {
        case .exposure: develop.exposure = value
        case .baselineExposure: develop.baselineExposure = value
        case .shadowBias: develop.shadowBias = value
        case .boost: develop.boostAmount = value
        case .boostShadow: develop.boostShadowAmount = value
        case .whiteBalance: develop.neutralTemperature = value
        case .sharpness: develop.sharpnessAmount = value
        case .contrast: develop.contrastAmount = value
        case .detail: develop.detailAmount = value
        case .moireReduction: develop.moireReductionAmount = value
        case .localToneMap: develop.localToneMapAmount = value
        case .luminanceNoiseReduction: develop.luminanceNoiseReductionAmount = value
        case .colorNoiseReduction: develop.colorNoiseReductionAmount = value
        case .lensCorrection: develop.lensCorrectionEnabled = value != 0
        case .gamutMapping: develop.gamutMappingEnabled = value != 0
        case .extendedDynamicRange: develop.extendedDynamicRangeAmount = value
        case .highlightRecovery: develop.highlightRecoveryEnabled = value != 0
        }
    }

    /// Return one control to "decoder default" — `nil`, not zero.
    func resetDevelop(_ control: DevelopControl) {
        updateDocument { document in
            switch control {
            case .exposure: document.rawDevelop.exposure = nil
            case .baselineExposure: document.rawDevelop.baselineExposure = nil
            case .shadowBias: document.rawDevelop.shadowBias = nil
            case .boost: document.rawDevelop.boostAmount = nil
            case .boostShadow: document.rawDevelop.boostShadowAmount = nil
            case .whiteBalance:
                document.rawDevelop.neutralTemperature = nil
                document.rawDevelop.neutralTint = nil
            case .sharpness: document.rawDevelop.sharpnessAmount = nil
            case .contrast: document.rawDevelop.contrastAmount = nil
            case .detail: document.rawDevelop.detailAmount = nil
            case .moireReduction: document.rawDevelop.moireReductionAmount = nil
            case .localToneMap: document.rawDevelop.localToneMapAmount = nil
            case .luminanceNoiseReduction: document.rawDevelop.luminanceNoiseReductionAmount = nil
            case .colorNoiseReduction: document.rawDevelop.colorNoiseReductionAmount = nil
            case .lensCorrection: document.rawDevelop.lensCorrectionEnabled = nil
            case .gamutMapping: document.rawDevelop.gamutMappingEnabled = nil
            case .extendedDynamicRange: document.rawDevelop.extendedDynamicRangeAmount = nil
            case .highlightRecovery: document.rawDevelop.highlightRecoveryEnabled = nil
            }
        }
    }

    /// Return every develop control to the decoder's defaults.
    func resetAllDevelop() {
        updateDocument { $0.rawDevelop = .neutral }
    }

    /// True when this control is a toggle rather than a slider.
    static func isToggle(_ control: DevelopControl) -> Bool {
        switch control {
        case .lensCorrection, .gamutMapping, .highlightRecovery: return true
        default: return false
        }
    }

    /// The slider range for a control. Values are `CIRAWFilter`'s documented ranges
    /// (`PHASE2_SPEC.md` §9 and `RAWDevelopSettings`).
    static func range(for control: DevelopControl) -> ClosedRange<Double> {
        switch control {
        case .exposure, .baselineExposure: return -4...4
        case .shadowBias: return -1...1
        case .boost, .boostShadow: return 0...2
        case .whiteBalance: return 2000...50000
        case .detail: return 0...3
        case .extendedDynamicRange: return 0...2
        case .lensCorrection, .gamutMapping, .highlightRecovery: return 0...1
        default: return 0...1
        }
    }
```

Add `import SwiftUI` to the top of `AppViewModel.swift` if not already present (it currently imports `AppKit` and `Combine`; `Binding` needs SwiftUI).

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DevelopInspectorTests`
Expected: PASS — `Executed 10 tests, with 0 failures`.

- [ ] **Step 5: Write the view**

Create `Sources/LUTzyKit/Views/DevelopInspectorView.swift`:

```swift
import SwiftUI

/// RAW develop controls, gated per image on what the file's decoder actually supports.
///
/// The control list is not written out here — it comes from `RAWCapabilities.availableControls`, so
/// which knobs appear is a value the tests can assert rather than a shape buried in a `ViewBuilder`.
/// An unsupported adjustment is **absent**, not greyed out: absence reads as "this camera's decoder
/// does not do that", where a disabled slider reads as "you did something wrong".
struct DevelopInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if let capabilities = viewModel.rawCapabilities {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        ForEach(capabilities.availableControls, id: \.self) { control in
                            controlRow(control)
                        }
                    }
                    .padding(16)
                }
            } else {
                notRAW
            }
        }
    }

    private var header: some View {
        HStack {
            Text("RAW Develop").font(.headline)
            Spacer()
            Button("Reset") { viewModel.resetAllDevelop() }
                .buttonStyle(.link)
                .disabled(viewModel.document.rawDevelop.isNeutral)
        }
    }

    /// Shown for a standard image. `RenderPipeline.developedSource` switches on `source.kind` and
    /// drops `rawDevelop` entirely for one, so offering the controls would be offering a lie.
    private var notRAW: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.aperture")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No develop stage")
                .font(.headline)
            Text("Develop controls come from the RAW decoder. This image is already rendered.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func controlRow(_ control: DevelopControl) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(control.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !AppViewModel.isToggle(control) {
                    Text(String(format: "%.2f", viewModel.developValue(for: control)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button {
                    viewModel.resetDevelop(control)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Reset to the decoder's default")
            }

            if AppViewModel.isToggle(control) {
                Toggle(control.title, isOn: Binding(
                    get: { viewModel.developValue(for: control) != 0 },
                    set: { viewModel.developBinding(for: control).wrappedValue = $0 ? 1 : 0 }
                ))
                .labelsHidden()
            } else {
                Slider(
                    value: viewModel.developBinding(for: control),
                    in: AppViewModel.range(for: control)
                )
                if control == .whiteBalance {
                    HStack {
                        Text("Tint").font(.caption2).foregroundStyle(.secondary)
                        Slider(value: viewModel.developTintBinding(), in: -150...150)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 6: Wire the segmented switch**

In `Sources/LUTzyKit/Views/InfoInspectorView.swift`, replace the `body` property with:

```swift
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $viewModel.inspectorTab) {
                ForEach(AppViewModel.InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            switch viewModel.inspectorTab {
            case .info:
                infoContent
            case .develop:
                DevelopInspectorView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 240, idealWidth: 280)
    }

    /// The original histogram + EXIF column, unchanged apart from being one branch of the switch.
    private var infoContent: some View {
        Group {
            if viewModel.sourceImage == nil {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        histogramSection
                        metadataSection
                    }
                    .padding(16)
                }
            }
        }
    }
```

- [ ] **Step 7: Verify the build and the whole suite**

Run: `swift build 2>&1 | grep -E "warning:|error:"`
Expected: no output.

Run: `swift test`
Expected: `0 failures`.

- [ ] **Step 8: Commit**

```bash
git add Sources/LUTzyKit/Views/DevelopInspectorView.swift Sources/LUTzyKit/Views/InfoInspectorView.swift Sources/LUTzyKit/ViewModels/AppViewModel.swift Tests/LUTzyKitTests/DevelopInspectorTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10a: the develop panel

A ForEach over RAWCapabilities.availableControls, in a segmented Info/Develop
switch at the top of the existing inspector.

Reading a control never writes. Every RAWDevelopSettings property is Optional
with nil meaning "decoder default", and .neutral is byte-identical to
developRAWNeutral because it sets nothing — so the getter falls back to the
decoder's own value and only the setter stores. Reset means unset, not zero.

A standard image gets an explanation rather than dead sliders: developedSource
drops rawDevelop entirely for one.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Pin the seeds against real pixels

**Files:**
- Test: `Tests/LUTzyKitTests/RAWCapabilitiesTests.swift` (append)

**Interfaces:**
- Consumes: everything above. No production changes — this task is pure verification, and it is the one that proves the panel is not lying about where its sliders start.

- [ ] **Step 1: Write the failing test**

Append to `RAWCapabilitiesTests`:

```swift
    // MARK: - The seeds are the decoder's actual values

    /// Writing the probed as-shot white balance must render identically to leaving it unset.
    ///
    /// This is the assumption the whole panel rests on: a slider bound to a `nil` setting displays
    /// the seed, so if the seed is not what the decoder actually used, every control opens on a
    /// value that is subtly not where the image is — and the first touch of any slider would jump
    /// the picture.
    ///
    /// Interleaved in one process; Core Image is not bit-reproducible across time-separated runs.
    /// Skips on CI, which has no DNG.
    func testWritingTheAsShotValuesMatchesLeavingThemUnset() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW; see Fixtures.localRAWURL and PHASE2_SPEC §8.9")
        }
        let engine = RenderEngine()
        let source = ImageSource(url: rawURL, nativeExtent: .zero)
        let caps = try XCTUnwrap(await engine.rawCapabilities(for: source))

        var written = EditDocument()
        written.rawDevelop.neutralTemperature = caps.asShotTemperature
        written.rawDevelop.neutralTint = caps.asShotTint

        let unsetImage = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: EditDocument(), lut: nil, scale: .full, space: .sRGB
        ))
        let writtenImage = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: written, lut: nil, scale: .full, space: .sRGB
        ))

        assertPixelsEqual(
            try Pixels.bytes(of: writtenImage, space: .sRGB),
            try Pixels.bytes(of: unsetImage, space: .sRGB),
            """
            writing the probed as-shot white balance changed the render, so the seed is not the \
            value the decoder actually used and every white-balance slider opens in the wrong place
            """
        )
    }

    /// The gate `CODE_REVIEW.md` §5 called untestable, asserted on pixels rather than on a flag:
    /// a value written to an unsupported adjustment must be dropped by `apply(to:)`.
    func testAValueWrittenToAnUnsupportedAdjustmentIsIgnored() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW; see Fixtures.localRAWURL and PHASE2_SPEC §8.9")
        }
        let engine = RenderEngine()
        let source = ImageSource(url: rawURL, nativeExtent: .zero)
        let caps = try XCTUnwrap(await engine.rawCapabilities(for: source))
        try XCTSkipIf(caps.isLocalToneMapSupported,
                      "this decoder now supports local tone mapping; pick another unsupported gate")

        var document = EditDocument()
        document.rawDevelop.localToneMapAmount = 1.0

        let neutral = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: EditDocument(), lut: nil, scale: .full, space: .sRGB
        ))
        let gated = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: document, lut: nil, scale: .full, space: .sRGB
        ))

        assertPixelsEqual(
            try Pixels.bytes(of: gated, space: .sRGB),
            try Pixels.bytes(of: neutral, space: .sRGB),
            "an unsupported adjustment must be dropped by apply(to:), not written to the filter"
        )
    }
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter RAWCapabilitiesTests`
Expected: PASS locally. These tests pass on first run rather than failing first, because they assert a property the code already has — they are characterization tests over `apply(to:)`'s existing gating, not new behaviour. Their value is proven by the mutation run in Task 7, not by a red-green cycle.

- [ ] **Step 3: Commit**

```bash
git add Tests/LUTzyKitTests/RAWCapabilitiesTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10a: pin the seeds and the gate against real pixels

Writing the probed as-shot white balance must render identically to leaving it
unset — the assumption the whole panel rests on, since a slider bound to nil
displays the seed.

And the is*Supported gate CODE_REVIEW §5 called untestable, asserted on pixels:
localToneMap is unsupported on the Leica DNG, so a value written to it must be
dropped by apply(to:).

Both skip on CI, which has no DNG.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Mutation-check, then docs and the PR

**Files:**
- Create: `scripts/mutate-step10a.sh`
- Modify: `docs/CODE_REVIEW.md`, `docs/PHASE2_SPEC.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the shippable step.

- [ ] **Step 1: Write the mutation harness**

Create `scripts/mutate-step10a.sh`. Copy `scripts/mutate-step9.sh` and replace the mutation list between `VM=...` and the `echo` summary block. Keep the classifier exactly as it is — it classifies on structure (`file.swift:LINE:COL: error:` for a compiler diagnostic versus `error: -[Suite test]` for a test failure), and the Step 9 lesson was that grepping message text for words like "cannot" misreports caught mutations as no-build.

```bash
VM=Sources/LUTzyKit/ViewModels/AppViewModel.swift
RC=Sources/LUTzyKit/Models/RAWCapabilities.swift
RE=Sources/LUTzyKit/Models/RenderEngine.swift

echo "=== gating ==="
mutate "RAWCapabilities: offer every control regardless of support" "$RC" \
  's/DevelopControl\.allCases\.filter\(supports\)/DevelopControl.allCases/' \
  "RAWCapabilitiesTests"
mutate "RAWCapabilities: a gated control reports supported" "$RC" \
  's/case \.localToneMap: return isLocalToneMapSupported/case .localToneMap: return true/' \
  "RAWCapabilitiesTests"
mutate "RAWCapabilities: an ungated control reports unsupported" "$RC" \
  's/             \.whiteBalance, \.gamutMapping, \.extendedDynamicRange:\n            \/\/ Ungated.*\n            return true/             .whiteBalance, .gamutMapping, .extendedDynamicRange:\n            return false/' \
  "RAWCapabilitiesTests"

echo "=== the probe ==="
mutate "RenderEngine: report capabilities for a standard image too" "$RE" \
  's/        guard case \.raw = source\.kind else \{ return nil \}\n//' \
  "RAWCapabilitiesTests|DevelopInspectorTests"
mutate "RenderEngine: return a blank capabilities value" "$RE" \
  's/            asShotTemperature: Double\(filter\.neutralTemperature\)/            asShotTemperature: 0/' \
  "RAWCapabilitiesTests|DevelopInspectorTests"
mutate "AppViewModel: never probe on open" "$VM" \
  's/                self\.refreshCapabilities\(\)\n//' \
  "DevelopInspectorTests"
mutate "AppViewModel: probe on every render" "$VM" \
  's/^        let \(requested, lut\) = displayRequest$/        refreshCapabilities()\n        let (requested, lut) = displayRequest/m' \
  "DevelopInspectorTests"

echo "=== debounce ==="
mutate "AppViewModel: ignore the debounce flag, always render immediately" "$VM" \
  's/        guard debounced else \{/        if true {/' \
  "DevelopInspectorTests"
mutate "AppViewModel: debounce drops the document update too" "$VM" \
  's/^        document = updated$/        if !debounced { document = updated }/m' \
  "DevelopInspectorTests|PreviewCutoverTests"

echo "=== nil semantics ==="
mutate "AppViewModel: an unset white balance reads back 0" "$VM" \
  's/case \.whiteBalance: return develop\.neutralTemperature \?\? seed\?\.asShotTemperature \?\? 6500/case .whiteBalance: return 0/' \
  "DevelopInspectorTests"
mutate "AppViewModel: reset writes zero instead of nil" "$VM" \
  's/            case \.exposure: document\.rawDevelop\.exposure = nil/            case .exposure: document.rawDevelop.exposure = 0/' \
  "DevelopInspectorTests"
mutate "AppViewModel: reading a control writes the seed" "$VM" \
  's/    func developValue\(for control: DevelopControl\) -> Double \{\n        let develop = document\.rawDevelop/    func developValue(for control: DevelopControl) -> Double {\n        document.rawDevelop.exposure = document.rawDevelop.exposure ?? 0\n        let develop = document.rawDevelop/' \
  "DevelopInspectorTests"
mutate "RAWDevelopSettings: write an unsupported adjustment anyway" \
  Sources/LUTzyKit/Models/RAWDevelopSettings.swift \
  's/if let localToneMapAmount, filter\.isLocalToneMapSupported \{/if let localToneMapAmount {/' \
  "RAWCapabilitiesTests"
```

- [ ] **Step 2: Run the harness**

Run: `chmod +x scripts/mutate-step10a.sh && ./scripts/mutate-step10a.sh`
Expected: every mutation reported `caught`, with `SURVIVED: 0`, `NO-BUILD: 0`, `NO-TESTS: 0`.

**If any mutation is reported NO-BUILD or NO-TESTS, the harness proved nothing for it** — fix the perl pattern or the filter and re-run, exactly as Step 9 had to. **If any SURVIVED, that is a coverage gap by default**: write the missing test rather than deleting the mutation. Only classify a survivor as equivalent after establishing it by inspection, and record the argument in a comment next to it — Step 9's one survivor is the template.

- [ ] **Step 3: Correct the CODE_REVIEW claim**

In `docs/CODE_REVIEW.md`, replace this bullet in the "Where coverage is still thin" list:

```markdown
- **The `CIRAWFilter` half of `RAWDevelopSettings` only runs where a RAW exists.** Three tests build a
  real filter from `Fixtures.localRAWURL` — the untracked `realworldtest/` DNG — and `XCTSkip` when
  there is none, which includes CI. The value semantics are covered everywhere; the framework wiring
  is covered only locally. The `is*Supported` gates in `apply(to:)` are not covered at all: that needs
  a RAW whose decoder *lacks* an adjustment, and the Leica file supports every one of them.
```

with:

```markdown
- **The `CIRAWFilter` half of `RAWDevelopSettings` only runs where a RAW exists.** Several tests build
  a real filter from `Fixtures.localRAWURL` — the untracked `realworldtest/` DNG — and `XCTSkip` when
  there is none, which includes CI. The value semantics are covered everywhere; the framework wiring
  is covered only locally.

  This entry used to claim the `is*Supported` gates "are not covered at all: that needs a RAW whose
  decoder *lacks* an adjustment, and the Leica file supports every one of them." **Measured in Phase 2
  Step 10a, that is wrong** — `isLocalToneMapSupported` is `false` on that file. The gated branch is
  covered locally now, on pixels:
  `RAWCapabilitiesTests.testAValueWrittenToAnUnsupportedAdjustmentIsIgnored`. Worth noting as a
  pattern: the claim was plausible, went unchecked for several steps, and cost nothing to disprove
  once someone printed the flags.
```

- [ ] **Step 4: Update the migration table**

In `docs/PHASE2_SPEC.md` §6, replace the Step 10 row:

```markdown
| 10 | RAW develop + adjustments inspector, gated per-image on the real `is*Supported` flags | inspector drives live re-render |
```

with:

```markdown
| ~~10a~~ | ~~RAW develop inspector + the per-image capability probe~~ | ✅ **done** — `RAWCapabilities` crosses the actor boundary; probe measured at ~25 ms vs ~183 ms for a develop, once per open |
| 10b | Adjustments inspector — fixed slots, one node of each, canonical pipeline order | inspector drives live re-render |
```

- [ ] **Step 5: Run the full ship gate**

```bash
swift build 2>&1 | grep -E "warning:|error:"
swift test 2>&1 | tail -3
swift build -c release 2>&1 | grep -E "warning:|error:"
```

Expected: the two `grep`s print nothing; `swift test` reports `0 failures`.

- [ ] **Step 6: Launch the release binary**

```bash
.build/release/LUTzy & sleep 8
osascript -e 'tell application "System Events" to tell (first process whose name contains "LUTzy") to get count of windows'
pkill -f ".build/release/LUTzy"
```

Expected: `1`. Note in the PR body that `swift run` produces no `.app` bundle, so the panel cannot be driven by the GUI automation tools — say what was verified headlessly instead of implying a hand click-through happened.

- [ ] **Step 7: Commit and open the PR**

```bash
git add scripts/mutate-step10a.sh docs/CODE_REVIEW.md docs/PHASE2_SPEC.md
git commit -m "$(cat <<'EOF'
Phase 2 Step 10a: mutation harness, and correct the untestable-gates claim

CODE_REVIEW §5 said the is*Supported gates could not be covered because the
Leica DNG "supports every one of them". Measured: isLocalToneMapSupported is
false, so the gated branch is covered locally now, on pixels.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push -u origin feature/phase2-develop-inspector
```

Then open a PR against `main` whose body states: the measured probe cost and why it is once per open; the nil-versus-written semantics and the test that pins the seeds; the mutation tally with any survivor named and argued; and — plainly — that the RAW-gated tests **skip on CI**, so a green tick says nothing about them.

---

## Self-Review

**Spec coverage.** §2 `RAWCapabilities` → Task 1. §2 probe → Task 2. §2 published/refreshed per open → Task 3. §3 nil-versus-value → Task 5 (bindings) and Task 6 (pixel proof). §4 debouncing → Task 4. §5 placement, source-kind gating, per-adjustment gating, `availableControls` as a value → Tasks 1 and 5. §6 every named test → Tasks 1, 3, 4, 5, 6; mutation harness → Task 7. §7 files → all tasks; doc corrections → Task 7. §8 out-of-scope items appear in no task, as intended.

**Deviations from the spec, deliberate.** The spec's `testOpeningThePanelWritesNothing` is implemented as `testReadingEveryControlWritesNothing` — the panel is a view, and this repo has no view tests, so the assertion drives every binding's getter instead, which is the thing that could write. Likewise `testUnsupportedAdjustmentsAreNotOffered` is split: `availableControls` gating in Task 1 against a synthetic capability value, and the real decoder's behaviour in Tasks 2 and 6.

**Task 6 has no red phase, and says so.** Both of its tests characterize gating that `apply(to:)` already implements, so they pass immediately; that is stated in the step rather than dressed up as TDD, and their worth is established by the Task 7 mutations instead.

**Type consistency.** `RAWCapabilities` field names match between Tasks 1, 2, 3 and 6. `DevelopControl` cases match between Tasks 1, 5 and 7. `developBinding(for:)`, `developValue(for:)`, `developTintBinding()`, `resetDevelop(_:)`, `resetAllDevelop()`, `isToggle(_:)` and `range(for:)` are defined in Task 5 and used only there and in its tests. `updateDocument(debounced:_:)` is defined in Task 4 and used in Task 5. `rawCapabilities(for:)` is defined in Task 2 and used in Tasks 3 and 6. `RenderPipeline.rawFilter(for:)` widens to internal in Task 2 and is used only there.

**One risk the executor should know.** Task 5's `Binding` requires `import SwiftUI` in `AppViewModel.swift`, which currently imports `AppKit` and `Combine`. If pulling SwiftUI into the view model is unwanted, the alternative is to move `developBinding`/`developTintBinding` into `DevelopInspectorView` and keep only `developValue(for:)`, `setDevelop` and the reset methods on the view model — but then the binding's write path is untestable, which is what the ship gate turns on. Raise it rather than silently choosing the untestable shape.
