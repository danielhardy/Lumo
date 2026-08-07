# Phase 2 Step 10b — Adjustments Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an inspector tab that writes `EditDocument.adjustments` — nine fixed per-parameter rows over the five existing `AdjustmentNode` cases — and drives a live re-render.

**Architecture:** A new `AdjustmentControl` value type holds all the logic as pure functions over `[AdjustmentNode]` (sparse: only non-identity nodes, kept in canonical order). `AppViewModel` gains four forwarding methods; a new `AdjustInspectorView` is a flat `ForEach` over the controls. `AdjustmentNode`, `RenderPipeline`, `RenderEngine` and `EditDocument` are **not modified** — if a task needs to touch them, the design is wrong, stop and raise it.

**Tech Stack:** Swift 6 language mode, SwiftUI, Core Image, XCTest. Zero third-party dependencies.

**Design doc:** `docs/superpowers/specs/2026-08-06-step10b-adjustments-inspector-design.md`

**Branch:** `feature/phase2-adjustments-inspector`, off `main`. Code lands as a reviewed PR (`CLAUDE.md`).

## Global Constraints

- **macOS 14 deployment target**, built against the macOS 26 SDK. Requires Xcode 26+. Any API newer than macOS 14 must be `#available`-guarded. None of this step's work needs new API.
- **Zero third-party dependencies.** Apple frameworks only. Do not add SPM/CocoaPods/Carthage deps.
- **Swift 6 language mode, zero escape hatches.** No `@unchecked Sendable`, no `nonisolated(unsafe)`, no `@preconcurrency` anywhere in `Sources/`. `PackageSettingsTests` fails if any appear.
- **`CIImage`/`CIFilter`/`CIContext` stay inside `RenderEngine`.** Only `Sendable` values cross the boundary. Nothing in this step should construct a `CIFilter` outside a test.
- Build: `swift build`. Test: `swift test`. Both must be clean before every commit.
- Only `ContentView` and `LUTzyCommands` are `public`. Everything added here is `internal` — write no access modifier.
- Commit messages end with the `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` trailer.
- **Fixtures are generated, never committed.** Use `Fixtures.swift` helpers; do not add binary test assets.
- RAW-dependent tests must `XCTSkip` when no DNG is present — CI has none.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/LUTzyKit/Models/AdjustmentControl.swift` | **New.** The nine controls, their titles/ranges/neutrals, the slot ordering, and the two pure sparse-array functions. All the logic. |
| `Sources/LUTzyKit/ViewModels/AppViewModel+Adjust.swift` | **New.** Four methods forwarding to the above and re-rendering. |
| `Sources/LUTzyKit/ViewModels/AppViewModel+Develop.swift` | **New.** Existing develop bindings, moved verbatim out of `AppViewModel.swift`. |
| `Sources/LUTzyKit/Views/AdjustInspectorView.swift` | **New.** Nine rows. One state. |
| `Sources/LUTzyKit/ViewModels/AppViewModel.swift` | Modify: `InspectorTab` gains `.adjust`; develop bindings move out; `isComparisonAvailable` added. |
| `Sources/LUTzyKit/Views/InfoInspectorView.swift` | Modify: third segment in the tab switcher. |
| `Sources/LUTzyKit/Views/PreviewView.swift` | Modify: two A/B gate call sites. |
| `Tests/LUTzyKitTests/AdjustmentControlTests.swift` | **New.** Pure-value tests: ranges, neutrals, the sparse contract, the temperature map. No engine, no GPU. |
| `Tests/LUTzyKitTests/AdjustInspectorTests.swift` | **New.** Wiring tests against `FakeRenderEngine`. |
| `Tests/LUTzyKitTests/RAWCapabilitiesTests.swift` | Modify: add the Kelvin-direction measurement. |
| `docs/PHASE2_SPEC.md` | Modify: §6 row 10b, and §8.5 / §8.6 / §8.7. |

---

## Task 1: Split `AppViewModel` (pure code motion)

`AppViewModel.swift` is 1004 lines before this step adds anything. Move the develop half out first, as its own commit, so the feature diff is readable. **No behavior change, no signature change, no test change.**

**Files:**
- Create: `Sources/LUTzyKit/ViewModels/AppViewModel+Develop.swift`
- Modify: `Sources/LUTzyKit/ViewModels/AppViewModel.swift` (remove lines 547–687, the `// MARK: - RAW develop` section)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing new. Every moved member keeps its exact name, signature and access level: `developBinding(for:)`, `developValue(for:)`, `developTintBinding()`, `setDevelop(_:to:in:)` (private static), `resetDevelop(_:)`, `resetAllDevelop()`.

- [ ] **Step 1: Create the branch**

```bash
git checkout main && git pull --ff-only && git checkout -b feature/phase2-adjustments-inspector
```

- [ ] **Step 2: Record the current test count**

Run: `swift test 2>&1 | tail -3`
Expected: a green run. Write the "Executed N tests" number down — Task 1 must not change it.

- [ ] **Step 3: Create the new file with the moved members**

Cut the entire `// MARK: - RAW develop` section out of `AppViewModel.swift` — from that MARK comment through the closing brace of `resetAllDevelop()` — and paste it into the new file, **doc comments included, verbatim**. Do not reword, reformat, or "improve" anything; a pure-motion commit that also edits prose is not reviewable as pure motion.

```swift
import SwiftUI

/// `AppViewModel`'s RAW develop bindings, split out at Step 10b.
///
/// Pure code motion — every member below arrived here unchanged from `AppViewModel.swift`, where it
/// was written in Step 10a. The split happened because Step 10b adds a second inspector panel's
/// worth of bindings to a file that had already reached 1004 lines, and a four-figure view model is
/// where the next reader stops being able to hold the whole thing in their head.
///
/// `private` members do not survive a file split in Swift — `setDevelop` is now `fileprivate`, which
/// is the same guarantee (nothing outside this file can call it) expressed at file scope.
extension AppViewModel {
    // ← the moved members go here, verbatim, with `private static func setDevelop`
    //    changed to `fileprivate static func setDevelop` and nothing else changed
}
```

**The one unavoidable change:** `setDevelop(_:to:in:)` is `private static` and is called from `developBinding(for:)`. Both move together into the same file, so change `private` to `fileprivate` on that one declaration. Nothing else changes. If the compiler demands any other access widening, stop — it means something did not move as a unit.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds clean, zero warnings.

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -3`
Expected: green, and **exactly** the test count from Step 2. A different count means something was dropped, not moved.

- [ ] **Step 6: Verify it really was pure motion**

Run: `git diff --stat main`
Expected: two files, and the lines added to `AppViewModel+Develop.swift` should be within a couple of lines of those removed from `AppViewModel.swift` (the difference being the new file's `import`, doc comment and `extension` wrapper).

- [ ] **Step 7: Commit**

```bash
git add Sources/LUTzyKit/ViewModels/AppViewModel.swift Sources/LUTzyKit/ViewModels/AppViewModel+Develop.swift
git commit -m "$(cat <<'EOF'
Split the develop bindings out of AppViewModel

Pure code motion ahead of Step 10b, which adds a second panel's worth of
bindings to a file already at 1004 lines. Every member moved verbatim;
the only edit is `setDevelop`'s `private` becoming `fileprivate`, since
`private` does not survive a file boundary and both it and its one caller
moved together.

Test count is unchanged, which is the check that this dropped nothing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Measure the Develop tab's Kelvin direction

The design (§5) makes "both Kelvin sliders agree" a requirement, and the direction of `CIRAWFilter.neutralTemperature` has never been measured in this repo. Measure it before writing the mapping that depends on it.

**Files:**
- Modify: `Tests/LUTzyKitTests/RAWCapabilitiesTests.swift` (append the test)

**Interfaces:**
- Consumes: nothing.
- Produces: **a measured fact**, recorded in the test's doc comment and carried into Task 6's mapping. Task 6 cannot be started until this task's output is known.

- [ ] **Step 1: Write the measurement test**

Append to `Tests/LUTzyKitTests/RAWCapabilitiesTests.swift`. The skip-and-locate idiom below is the one
already used by `testProbingARealRAWReportsItsDecodersFlags` — `Fixtures.localRAWURL` finds the first
RAW in `realworldtest/`, and `ImageSource(url:nativeExtent:)` takes `.zero` because the probe does not
read the extent. Do not invent a second way of locating the fixture.

```swift
/// **Which way does the Develop tab's white-balance slider go?**
///
/// `PHASE2_SPEC.md` §8.7 measured `CITemperatureAndTint` — the *adjustment* node — and found that
/// raising Kelvin cools, inverting the photographic convention. `CIRAWFilter.neutralTemperature` is
/// a different knob with different semantics: it declares the illuminant the decoder should treat as
/// neutral, so it should move the opposite way. "Should" is not a measurement, and Step 10b puts
/// both sliders in the same inspector, where disagreeing directions would be indefensible.
///
/// Renders the same RAW at 3200 K and 9000 K with everything else at the decoder's default, and
/// compares the red/blue balance. Skips without a DNG, so CI proves nothing here.
func testRaisingNeutralTemperatureWarmsTheImage() async throws {
    guard let rawURL = Fixtures.localRAWURL else {
        throw XCTSkip("no local RAW; see Fixtures.localRAWURL and PHASE2_SPEC §8.9")
    }
    let engine = RenderEngine()
    let source = ImageSource(url: rawURL, nativeExtent: .zero)

    /// Mean red minus mean blue over the whole frame. Positive is warm.
    ///
    /// `Pixels.bytes(of:)` (in `PixelAssertions.swift`) returns tightly-packed RGBA8, and is the
    /// only pixel-reading helper this suite has; there is no mean-channel helper, and this one test
    /// does not warrant adding one to a file every other test shares.
    func meanRedMinusBlue(at kelvin: Double) async throws -> Double {
        var develop = RAWDevelopSettings.neutral
        develop.neutralTemperature = kelvin
        let document = EditDocument(rawDevelop: develop)

        // `XCTUnwrap` takes an autoclosure, which cannot contain `await` — hop first, unwrap after.
        let rendered = await engine.makeCGImage(
            source: source, document: document, lut: nil,
            scale: .preview(maxSize: CGSize(width: 400, height: 400)), space: .current
        )
        let cgImage = try XCTUnwrap(rendered)
        let bytes = try Pixels.bytes(of: cgImage)

        var redTotal = 0, blueTotal = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            redTotal += Int(bytes[pixel])
            blueTotal += Int(bytes[pixel + 2])
        }
        let pixelCount = Double(bytes.count / 4)
        return (Double(redTotal) - Double(blueTotal)) / pixelCount
    }

    let warmEnd = try await meanRedMinusBlue(at: 3200)
    let coolEnd = try await meanRedMinusBlue(at: 9000)

    print("MEASURED CIRAWFilter.neutralTemperature: R−B at 3200 K = \(warmEnd), at 9000 K = \(coolEnd)")

    XCTAssertNotEqual(warmEnd, coolEnd, accuracy: 0.5,
                      "the knob must actually move the picture, or the rest of this says nothing")
    XCTAssertGreaterThan(
        coolEnd, warmEnd,
        "raising neutralTemperature is expected to WARM the image (more red relative to blue), "
        + "the opposite of CITemperatureAndTint. If this fails, the two knobs agree already and "
        + "Step 10b's Adjust temperature mapping must be the identity — see the design doc §5."
    )
}
```

- [ ] **Step 2: Run it**

Run: `swift test --filter testRaisingNeutralTemperatureWarmsTheImage 2>&1 | tail -20`

Expected: either PASS with the `MEASURED …` line printed, or a skip if no DNG is reachable. **If it skips, stop and tell the user** — Task 6 depends on this number and guessing it defeats the point of the task.

- [ ] **Step 3: Record the outcome in the test's doc comment**

Replace the "should" language with the measured numbers, in the style of `DevelopControl.range`'s observational notes — name the camera, give the two values, and say that it is one camera's worth of data.

- [ ] **Step 4: Commit**

```bash
git add Tests/LUTzyKitTests/RAWCapabilitiesTests.swift
git commit -m "$(cat <<'EOF'
Measure which way the develop tab's Kelvin slider goes

PHASE2_SPEC.md §8.7 measured CITemperatureAndTint and found raising Kelvin
cools. CIRAWFilter.neutralTemperature is a different knob and had never
been measured here at all. Step 10b puts both sliders in one inspector,
so the direction stops being academic.

Skips without a DNG; CI proves nothing about this one.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `AdjustmentSlot` and the nine controls

**Files:**
- Create: `Sources/LUTzyKit/Models/AdjustmentControl.swift`
- Test: `Tests/LUTzyKitTests/AdjustmentControlTests.swift`

**Interfaces:**
- Consumes: `AdjustmentNode` (read-only — do not modify that file).
- Produces:
  - `enum AdjustmentSlot: Int, Sendable, CaseIterable, Comparable` with cases `exposure, colorControls, highlightShadow, temperatureTint, vibrance` (raw values 0–4).
  - `var AdjustmentNode.slot: AdjustmentSlot`
  - `var AdjustmentSlot.neutralNode: AdjustmentNode`
  - `var AdjustmentSlot.controls: [AdjustmentControl]`
  - `func AdjustmentSlot.node(from values: [AdjustmentControl: Double]) -> AdjustmentNode`
  - `enum AdjustmentControl: String, Sendable, CaseIterable, Hashable` with cases `exposure, brightness, contrast, saturation, highlights, shadows, temperature, tint, vibrance`
  - `var AdjustmentControl.title: String`, `.neutral: Double`, `.range: ClosedRange<Double>`, `.slot: AdjustmentSlot`

- [ ] **Step 1: Write the failing tests**

Create `Tests/LUTzyKitTests/AdjustmentControlTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AdjustmentControlTests 2>&1 | tail -20`
Expected: FAIL — compile error, `cannot find 'AdjustmentSlot' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/LUTzyKit/Models/AdjustmentControl.swift`:

```swift
import Foundation

/// Which `AdjustmentNode` case a control belongs to, and where that node sits in the pipeline.
///
/// The raw values **are** the canonical order — `AdjustmentNode`'s own case-declaration order, which
/// is what `PHASE2_SPEC.md` §3 shows and what `RenderPipeline.applyAdjustments` folds. `Comparable`
/// on the raw value is what lets a sparse array stay sorted without a separate sort key.
enum AdjustmentSlot: Int, Sendable, CaseIterable, Comparable {
    case exposure = 0
    case colorControls
    case highlightShadow
    case temperatureTint
    case vibrance

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// A node of this slot's case that does nothing. The seed a control reads through to when the
    /// document holds no node for this slot, and the base a write is applied to.
    var neutralNode: AdjustmentNode {
        switch self {
        case .exposure: return .neutralExposure
        case .colorControls: return .neutralColorControls
        case .highlightShadow: return .neutralHighlightShadow
        case .temperatureTint: return .neutralTemperatureTint
        case .vibrance: return .neutralVibrance
        }
    }

    /// The controls that together fill this slot's node, in row order.
    var controls: [AdjustmentControl] {
        AdjustmentControl.allCases.filter { $0.slot == self }
    }

    /// Rebuild this slot's node from its controls' values.
    ///
    /// **No `default:` arm, deliberately** — the same reasoning as `DevelopControl.isToggle`. A sixth
    /// slot must be a compile error naming this file, not a silently-dropped adjustment.
    func node(from values: [AdjustmentControl: Double]) -> AdjustmentNode {
        func v(_ control: AdjustmentControl) -> Double { values[control] ?? control.neutral }
        switch self {
        case .exposure:
            return .exposure(ev: v(.exposure))
        case .colorControls:
            return .colorControls(brightness: v(.brightness), contrast: v(.contrast),
                                  saturation: v(.saturation))
        case .highlightShadow:
            return .highlightShadow(highlights: v(.highlights), shadows: v(.shadows))
        case .temperatureTint:
            return .temperatureTint(temp: v(.temperature), tint: v(.tint))
        case .vibrance:
            return .vibrance(amount: v(.vibrance))
        }
    }
}

extension AdjustmentNode {
    /// Which slot this node occupies. Total and exhaustive; there is no "other".
    var slot: AdjustmentSlot {
        switch self {
        case .exposure: return .exposure
        case .colorControls: return .colorControls
        case .highlightShadow: return .highlightShadow
        case .temperatureTint: return .temperatureTint
        case .vibrance: return .vibrance
        }
    }
}

/// One row in the Adjust inspector.
///
/// The `DevelopControl` analogue, and deliberately the same shape: a value rather than a set of
/// `if`s in a `ViewBuilder`, so which rows exist and what each one does can be asserted without
/// instantiating a view — this repo has no SwiftUI view tests. **The declaration order below is the
/// panel's layout order**, and it is canonical pipeline order with the multi-parameter nodes
/// expanded in place.
///
/// Nine rows over five nodes, rather than five rows with sub-sliders: "Colour Controls" is a
/// `CIFilter` name, not a photographer's, and grouping three unrelated knobs under it leaks an
/// implementation detail into the UI. See the Step 10b design doc §2.
enum AdjustmentControl: String, Sendable, CaseIterable, Hashable {
    case exposure
    case brightness
    case contrast
    case saturation
    case highlights
    case shadows
    case temperature
    case tint
    case vibrance

    var slot: AdjustmentSlot {
        switch self {
        case .exposure: return .exposure
        case .brightness, .contrast, .saturation: return .colorControls
        case .highlights, .shadows: return .highlightShadow
        case .temperature, .tint: return .temperatureTint
        case .vibrance: return .vibrance
        }
    }

    var title: String {
        switch self {
        case .exposure: return "Exposure"
        case .brightness: return "Brightness"
        case .contrast: return "Contrast"
        case .saturation: return "Saturation"
        case .highlights: return "Highlights"
        case .shadows: return "Shadows"
        case .temperature: return "Temperature"
        case .tint: return "Tint"
        case .vibrance: return "Vibrance"
        }
    }

    /// The value at which this control does nothing.
    ///
    /// Every one of these equals the value `AdjustmentNode.isIdentity` names *and* the filter's own
    /// `kCIAttributeIdentity`, checked by probing the runtime `CIFilter.attributes` dictionary on the
    /// macOS 26 SDK. `testEveryControlsNeutralMatchesTheNodesIdentity` asserts the first half of that
    /// agreement on every run; the second half was a one-off measurement, recorded on `range`.
    var neutral: Double {
        switch self {
        case .exposure: return 0
        case .brightness: return 0
        case .contrast: return 1
        case .saturation: return 1
        case .highlights: return 1
        case .shadows: return 0
        case .temperature: return 6500
        case .tint: return 0
        case .vibrance: return 0
        }
    }

    /// The slider range.
    ///
    /// **Measured, not guessed.** `CIFilterBuiltins.h` documents no ranges at all — only prose. The
    /// numbers live in the runtime `CIFilter.attributes` dictionary, probed directly on the macOS 26
    /// SDK. What it reports, as `kCIAttributeSliderMin…Max` with `kCIAttributeIdentity` in brackets:
    /// `inputEV` −10…10 [0], `inputBrightness` −1…1 [0], `inputContrast` 0.25…4 [1],
    /// `inputSaturation` 0…2 [1], `inputHighlightAmount` **0.3…1** [1], `inputShadowAmount` −1…1 [0],
    /// `inputAmount` (vibrance) −1…1 [0]. `CITemperatureAndTint` reports no range, because its
    /// parameters are `CIVector`s.
    ///
    /// Three rows need their reasoning recorded, because each is a place a later reader would
    /// otherwise assume a mistake:
    ///
    /// **Exposure is narrowed to −4…4**, though the filter accepts −10…10. `DevelopControl.exposure`
    /// is −4…4 — a UI throw chosen in 10a, not a framework limit — and two exposure sliders one
    /// inspector tab apart with different travel is worse than either range on its own. Widen both
    /// together or neither.
    ///
    /// **Highlights runs 0.3…1 with its identity at the maximum.** That floor is the filter's, not
    /// ours. The slider therefore travels one way only: down, recovering highlights. It is the sole
    /// exception to "every neutral sits strictly inside its range" — see
    /// `testEveryNeutralSitsInsideItsRangeExceptHighlights`.
    ///
    /// **Temperature is 2000…11000 K, narrower than `DevelopControl.whiteBalance`'s 2000…50000.**
    /// Forced by the inversion, not chosen for taste — see `sliderMapped(_:)`.
    var range: ClosedRange<Double> {
        switch self {
        case .exposure: return -4...4
        case .brightness: return -1...1
        case .contrast: return 0.25...4
        case .saturation: return 0...2
        case .highlights: return 0.3...1
        case .shadows: return -1...1
        case .temperature: return 2000...11000
        case .tint: return -150...150
        case .vibrance: return -1...1
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter AdjustmentControlTests 2>&1 | tail -10`
Expected: PASS, all five tests.

- [ ] **Step 5: Build and run the whole suite**

Run: `swift build && swift test 2>&1 | tail -3`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add Sources/LUTzyKit/Models/AdjustmentControl.swift Tests/LUTzyKitTests/AdjustmentControlTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10b: the nine adjustment controls

The DevelopControl analogue — nine per-parameter rows over the five
AdjustmentNode cases, in canonical pipeline order, with an AdjustmentSlot
that carries the ordering so a sparse array can stay sorted without a
separate key.

Ranges are probed off the runtime CIFilter.attributes dictionary; the
headers document none. That turned up inputHighlightAmount's floor of 0.3
with its identity at the range maximum, which is the one documented
exception to the neutral-inside-range check.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: The sparse contract

**Files:**
- Modify: `Sources/LUTzyKit/Models/AdjustmentControl.swift` (extend `AdjustmentControl`)
- Modify: `Tests/LUTzyKitTests/AdjustmentControlTests.swift`

**Interfaces:**
- Consumes: `AdjustmentSlot`, `AdjustmentControl` from Task 3.
- Produces:
  - `func AdjustmentControl.value(in adjustments: [AdjustmentNode]) -> Double`
  - `func AdjustmentControl.setting(_ value: Double, in adjustments: [AdjustmentNode]) -> [AdjustmentNode]`

- [ ] **Step 1: Write the failing tests**

Append to `AdjustmentControlTests.swift`:

```swift
// MARK: - The sparse contract

extension AdjustmentControlTests {

    /// Every control's neutral must be the value `AdjustmentNode.isIdentity` already names.
    ///
    /// Looped rather than spelled out nine times, so a tenth control cannot ship with a neutral that
    /// silently disagrees with the model — which would show a slider parked away from where the
    /// picture actually is, the same defect 10a's white-balance seed was added to prevent.
    func testEveryControlsNeutralMatchesTheNodesIdentity() {
        for slot in AdjustmentSlot.allCases {
            for control in slot.controls {
                XCTAssertEqual(
                    control.value(in: [slot.neutralNode]), control.neutral, accuracy: 1e-12,
                    "\(control)'s neutral disagrees with its node's identity value"
                )
            }
        }
    }

    /// Reading a control whose node is absent returns its neutral. This is what lets the document
    /// stay empty until the user actually touches something — the same "reading never writes"
    /// property `developBinding(for:)` has, and for the same reason: seeding every field when the
    /// panel opened would silently make every document non-neutral.
    func testReadingAnAbsentNodeReturnsNeutral() {
        for control in AdjustmentControl.allCases {
            XCTAssertEqual(control.value(in: []), control.neutral, accuracy: 1e-12, "\(control)")
        }
    }

    /// Writing a non-neutral value into an empty document creates exactly one node.
    func testWritingCreatesExactlyOneNode() {
        let result = AdjustmentControl.contrast.setting(1.4, in: [])
        XCTAssertEqual(result, [.colorControls(brightness: 0, contrast: 1.4, saturation: 1)])
    }

    /// Round-trip: what you write is what you read, for every control.
    func testEveryControlRoundTrips() {
        for control in AdjustmentControl.allCases {
            // A value that is inside the range and is definitely not the neutral.
            let midpoint = (control.range.lowerBound + control.range.upperBound) / 2
            let value = midpoint == control.neutral
                ? (midpoint + control.range.upperBound) / 2
                : midpoint
            XCTAssertNotEqual(value, control.neutral, "\(control): test value must not be neutral")

            let written = control.setting(value, in: [])
            XCTAssertEqual(control.value(in: written), value, accuracy: 1e-12, "\(control)")
        }
    }

    /// Writing one parameter must not disturb its siblings in the same node.
    func testWritingOneParameterPreservesItsSiblings() {
        var adjustments = AdjustmentControl.contrast.setting(1.4, in: [])
        adjustments = AdjustmentControl.saturation.setting(0.5, in: adjustments)

        XCTAssertEqual(AdjustmentControl.contrast.value(in: adjustments), 1.4, accuracy: 1e-12)
        XCTAssertEqual(AdjustmentControl.saturation.value(in: adjustments), 0.5, accuracy: 1e-12)
        XCTAssertEqual(AdjustmentControl.brightness.value(in: adjustments), 0, accuracy: 1e-12)
        XCTAssertEqual(adjustments.count, 1, "all three share one colorControls node")
    }

    /// Returning the last non-neutral parameter of a node to its neutral removes the node entirely.
    /// This is what keeps `EditDocument() == []` true after an edit is undone by hand, which §5's
    /// "empty document is identity" invariant and `originalForComparison` both rest on.
    func testReturningToNeutralRemovesTheNode() {
        var adjustments = AdjustmentControl.contrast.setting(1.4, in: [])
        XCTAssertEqual(adjustments.count, 1)

        adjustments = AdjustmentControl.contrast.setting(AdjustmentControl.contrast.neutral, in: adjustments)
        XCTAssertEqual(adjustments, [], "a node at its identity must not linger in the document")
    }

    /// A node whose siblings are still non-neutral must survive one parameter going back to neutral.
    func testReturningOneParameterToNeutralKeepsANodeItsSiblingsStillNeed() {
        var adjustments = AdjustmentControl.contrast.setting(1.4, in: [])
        adjustments = AdjustmentControl.saturation.setting(0.5, in: adjustments)
        adjustments = AdjustmentControl.contrast.setting(1, in: adjustments)

        XCTAssertEqual(adjustments, [.colorControls(brightness: 0, contrast: 1, saturation: 0.5)])
    }

    /// **Inserted at the canonical index, not appended.** Order is meaningful to the render —
    /// `AdjustmentNode`'s doc comment is explicit that exposure-then-colorControls is not the same
    /// picture as the reverse — so writing the rows out of order must not produce a different graph
    /// from writing them in order.
    func testNodesLandInCanonicalOrderWhateverOrderTheyAreWrittenIn() {
        var backwards: [AdjustmentNode] = []
        backwards = AdjustmentControl.vibrance.setting(0.3, in: backwards)
        backwards = AdjustmentControl.temperature.setting(5000, in: backwards)
        backwards = AdjustmentControl.shadows.setting(0.2, in: backwards)
        backwards = AdjustmentControl.saturation.setting(1.2, in: backwards)
        backwards = AdjustmentControl.exposure.setting(0.5, in: backwards)

        XCTAssertEqual(backwards.map(\.slot), [.exposure, .colorControls, .highlightShadow,
                                               .temperatureTint, .vibrance])

        var forwards: [AdjustmentNode] = []
        forwards = AdjustmentControl.exposure.setting(0.5, in: forwards)
        forwards = AdjustmentControl.saturation.setting(1.2, in: forwards)
        forwards = AdjustmentControl.shadows.setting(0.2, in: forwards)
        forwards = AdjustmentControl.temperature.setting(5000, in: forwards)
        forwards = AdjustmentControl.vibrance.setting(0.3, in: forwards)

        XCTAssertEqual(backwards, forwards, "write order must not change the resulting graph")
    }

    /// No slot may ever appear twice. The UI is one-of-each even though the model permits stacking.
    func testNoSlotEverAppearsTwice() {
        var adjustments: [AdjustmentNode] = []
        for control in AdjustmentControl.allCases {
            let value = control == .highlights ? 0.5 : control.range.upperBound
            adjustments = control.setting(value, in: adjustments)
        }
        let slots = adjustments.map(\.slot)
        XCTAssertEqual(slots.count, Set(slots).count, "a slot appeared twice: \(slots)")
        XCTAssertEqual(slots, AdjustmentSlot.allCases, "all five slots, once each, in order")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AdjustmentControlTests 2>&1 | tail -20`
Expected: FAIL — compile error, `value of type 'AdjustmentControl' has no member 'value'`.

- [ ] **Step 3: Write the implementation**

Append to `Sources/LUTzyKit/Models/AdjustmentControl.swift`:

```swift
// MARK: - The sparse contract

/// `EditDocument.adjustments` holds **only non-identity nodes**, kept in canonical order.
///
/// A row sitting at its neutral value contributes nothing to the array, which is what keeps
/// `EditDocument()` equal to `[]` — and with it §5's "empty document is identity" invariant, and
/// `originalForComparison`, which sets `adjustments: []` to build the A/B baseline. It also keeps
/// Step 11's undo snapshots small, since an untouched panel costs nothing to snapshot.
///
/// Both functions are pure — no view model, no `CIContext`, no image — which is what lets the whole
/// contract be asserted on CI.
extension AdjustmentControl {

    /// This control's current value: the stored one, or its neutral when no node holds it.
    ///
    /// **No `default:` arm** — exhaustive over `self`, so a tenth control is a compile error naming
    /// this file rather than a row that silently always reads neutral.
    func value(in adjustments: [AdjustmentNode]) -> Double {
        let node = adjustments.first { $0.slot == slot }
        switch self {
        case .exposure:
            guard case .exposure(let ev)? = node else { return neutral }
            return ev
        case .brightness:
            guard case .colorControls(let brightness, _, _)? = node else { return neutral }
            return brightness
        case .contrast:
            guard case .colorControls(_, let contrast, _)? = node else { return neutral }
            return contrast
        case .saturation:
            guard case .colorControls(_, _, let saturation)? = node else { return neutral }
            return saturation
        case .highlights:
            guard case .highlightShadow(let highlights, _)? = node else { return neutral }
            return highlights
        case .shadows:
            guard case .highlightShadow(_, let shadows)? = node else { return neutral }
            return shadows
        case .temperature:
            guard case .temperatureTint(let temp, _)? = node else { return neutral }
            return temp
        case .tint:
            guard case .temperatureTint(_, let tint)? = node else { return neutral }
            return tint
        case .vibrance:
            guard case .vibrance(let amount)? = node else { return neutral }
            return amount
        }
    }

    /// `adjustments` with this control set to `value` — still sparse, still in canonical order.
    ///
    /// Rebuilds the whole node from its controls (each read through `value(in:)`, so an absent node
    /// reads as neutral), then inserts it at its canonical index or drops it, according to
    /// `isIdentity`. Insertion is by slot rather than appended: order is meaningful to the render, so
    /// writing the rows bottom-up must produce the same graph as writing them top-down.
    func setting(_ value: Double, in adjustments: [AdjustmentNode]) -> [AdjustmentNode] {
        var values: [AdjustmentControl: Double] = [:]
        for sibling in slot.controls { values[sibling] = sibling.value(in: adjustments) }
        values[self] = value

        var result = adjustments.filter { $0.slot != slot }
        let updated = slot.node(from: values)
        guard !updated.isIdentity else { return result }

        let index = result.firstIndex { $0.slot > slot } ?? result.count
        result.insert(updated, at: index)
        return result
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter AdjustmentControlTests 2>&1 | tail -10`
Expected: PASS, all tests including the one uncommented in Step 1.

- [ ] **Step 5: Run the whole suite**

Run: `swift build && swift test 2>&1 | tail -3`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add Sources/LUTzyKit/Models/AdjustmentControl.swift Tests/LUTzyKitTests/AdjustmentControlTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10b: the sparse adjustments contract

The array holds only non-identity nodes, in canonical order. Writing a
value rebuilds its whole node from its sibling controls and then inserts
at the canonical index or drops the node, so a row returned to neutral
leaves nothing behind and writing the panel bottom-up produces the same
graph as top-down.

Sparseness is what keeps EditDocument() == [] true, which §5's "empty
document is identity" invariant and originalForComparison both rest on.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: The temperature mapping

**Depends on Task 2's measurement.** Do not start this task until that number is known.

**Files:**
- Modify: `Sources/LUTzyKit/Models/AdjustmentControl.swift`
- Modify: `Tests/LUTzyKitTests/AdjustmentControlTests.swift`

**Interfaces:**
- Consumes: `AdjustmentControl.range`, `.neutral` from Task 3.
- Produces: `func AdjustmentControl.sliderMapped(_ value: Double) -> Double` — a self-inverse map between what the slider shows and what the node stores. Used in **both** directions by Task 6's binding.

- [ ] **Step 1: Branch on Task 2's result**

- **If Task 2 measured that raising `neutralTemperature` warms** (the expected outcome): the two knobs disagree, so implement the inversion exactly as written below.
- **If Task 2 measured that raising it cools**: the two knobs already agree. Implement `sliderMapped` as the identity for every control, keep the doc comment explaining why no inversion was needed, **change `AdjustmentControl.temperature.range` to `2000...50000`** to match `DevelopControl.whiteBalance`, and drop the involution test in favour of one asserting the map is the identity. Tell the user this branch was taken — it contradicts the design doc §5, which will need amending in Task 10.

The rest of this task assumes the first branch.

- [ ] **Step 2: Write the failing tests**

Append to `AdjustmentControlTests.swift`:

```swift
// MARK: - The temperature mapping

extension AdjustmentControlTests {

    /// The map is its own inverse, which is what lets one function serve both directions of the
    /// binding. A non-involutive map would need two functions that could drift apart.
    func testTheSliderMapIsItsOwnInverse() {
        for control in AdjustmentControl.allCases {
            for value in [control.range.lowerBound, control.neutral, control.range.upperBound] {
                XCTAssertEqual(control.sliderMapped(control.sliderMapped(value)), value,
                               accuracy: 1e-9, "\(control) at \(value)")
            }
        }
    }

    /// Only temperature maps. Everything else is the identity, and stays that way.
    func testOnlyTemperatureIsMapped() {
        for control in AdjustmentControl.allCases where control != .temperature {
            let midpoint = (control.range.lowerBound + control.range.upperBound) / 2
            XCTAssertEqual(control.sliderMapped(midpoint), midpoint, accuracy: 1e-12, "\(control)")
        }
    }

    /// **The reason the range is 2000…11000 and not Develop's 2000…50000.** The reflection must land
    /// back inside the range at both ends, or the slider has a dead zone at one end and demands a
    /// negative colour temperature at the other. Reflecting 2000…50000 about 6500 would ask
    /// `CITemperatureAndTint` for −37000 K.
    func testTheTemperatureRangeIsClosedUnderTheReflection() {
        let range = AdjustmentControl.temperature.range
        for value in [range.lowerBound, range.upperBound] {
            XCTAssertTrue(range.contains(AdjustmentControl.temperature.sliderMapped(value)),
                          "\(value) K reflects to \(AdjustmentControl.temperature.sliderMapped(value)) K, "
                          + "outside \(range)")
        }
    }

    /// Neutral is the fixed point, so identity survives the map — a panel at its defaults must still
    /// produce an empty adjustments array.
    func testNeutralIsTheFixedPointOfTheMap() {
        XCTAssertEqual(AdjustmentControl.temperature.sliderMapped(6500), 6500, accuracy: 1e-12)
    }

    /// Dragging the slider **right** must warm the picture, matching the Develop tab's white-balance
    /// slider and every other photo application. Since the node's own Kelvin cools as it rises
    /// (`PHASE2_SPEC.md` §8.7, `testRaisingKelvinCoolsTheImage`), a higher slider value has to reach
    /// the node as a *lower* stored temperature.
    func testDraggingRightWarmsByStoringALowerNodeTemperature() {
        let cool = AdjustmentControl.temperature.sliderMapped(3000)
        let warm = AdjustmentControl.temperature.sliderMapped(10000)
        XCTAssertLessThan(warm, cool,
                          "a higher slider reading must store a lower node temperature, because the "
                          + "node's Kelvin runs backwards — see PHASE2_SPEC.md §8.7")
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter AdjustmentControlTests 2>&1 | tail -20`
Expected: FAIL — `has no member 'sliderMapped'`.

- [ ] **Step 4: Write the implementation**

Append to `Sources/LUTzyKit/Models/AdjustmentControl.swift`:

```swift
// MARK: - Slider ↔ model mapping

extension AdjustmentControl {

    /// Convert between what the slider reads and what the node stores. **Self-inverse**, so one
    /// function serves both directions and they cannot drift apart.
    ///
    /// The identity for eight of the nine controls. Temperature is the exception, and the reason is
    /// measured rather than assumed:
    ///
    /// `RenderPipeline` pins `CITemperatureAndTint.neutral` at D65 and moves only `targetNeutral`,
    /// which makes the node's Kelvin run **backwards** — 3200 K warms, 9000 K cools
    /// (`PHASE2_SPEC.md` §8.7, pinned by `testRaisingKelvinCoolsTheImage`). `CIRAWFilter`'s
    /// `neutralTemperature`, one inspector tab away, runs the photographic way round
    /// (`RAWCapabilitiesTests.testRaisingNeutralTemperatureWarmsTheImage`). Two Kelvin sliders in one
    /// inspector that move opposite ways is not a defensible thing to ship, so this reflects the
    /// adjustment slider about D65 and the Develop slider is left alone.
    ///
    /// **The reflection is why the temperature range is 2000…11000 rather than Develop's
    /// 2000…50000.** `13000 − K` maps 2000…50000 onto 11000…−37000, and negative Kelvin is not a
    /// colour. A range symmetric about 6500 makes the map a closed involution over itself: no
    /// clamping, no dead zone, and 6500 as the fixed point so identity survives the round trip.
    /// 2000…11000 is also the more useful photographic throw — Develop's upper bound is
    /// `CIRAWFilter`'s documented limit, which is a limit rather than a recommendation.
    ///
    /// The model still stores filter-native values. Reversing this decision later means changing
    /// this one function.
    func sliderMapped(_ value: Double) -> Double {
        switch self {
        case .temperature:
            return 2 * Self.temperaturePivot - value
        case .exposure, .brightness, .contrast, .saturation, .highlights, .shadows, .tint, .vibrance:
            return value
        }
    }

    /// D65 — the fixed point of the temperature reflection, and `temperatureTint`'s identity.
    private static let temperaturePivot: Double = 6500
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter AdjustmentControlTests 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 6: Run the whole suite and commit**

Run: `swift build && swift test 2>&1 | tail -3`
Expected: green.

```bash
git add Sources/LUTzyKit/Models/AdjustmentControl.swift Tests/LUTzyKitTests/AdjustmentControlTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10b: make both Kelvin sliders agree

The adjustment node's Kelvin runs backwards (§8.7, measured at Step 3);
CIRAWFilter's runs the photographic way round (measured in Task 2). Two
Kelvin sliders in one inspector moving opposite ways is not shippable, so
the adjustment slider reflects about D65 and Develop is left alone.

The reflection is also why this slider is 2000…11000 K and not Develop's
2000…50000: 13000 − K maps that range onto 11000…−37000, and negative
Kelvin is not a colour. Symmetric about the pivot, the map is a closed
involution — one function, both directions, no clamping, no dead zone.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: The view-model bindings

**Files:**
- Create: `Sources/LUTzyKit/ViewModels/AppViewModel+Adjust.swift`
- Test: `Tests/LUTzyKitTests/AdjustInspectorTests.swift`

**Interfaces:**
- Consumes: `AdjustmentControl.value(in:)`, `.setting(_:in:)`, `.sliderMapped(_:)`, `.neutral`; `AppViewModel.updateDocument(debounced:_:)`, `.document`.
- Produces:
  - `func AppViewModel.adjustmentValue(for control: AdjustmentControl) -> Double` — **slider-space**, already mapped.
  - `func AppViewModel.adjustmentBinding(for control: AdjustmentControl) -> Binding<Double>` — slider-space both ways, debounced.
  - `func AppViewModel.resetAdjustment(_ control: AdjustmentControl)` — undebounced.
  - `func AppViewModel.resetAllAdjustments()` — undebounced.
  - `var AppViewModel.hasAdjustments: Bool` — for the header's Reset button.

- [ ] **Step 1: Write the failing tests**

Create `Tests/LUTzyKitTests/AdjustInspectorTests.swift`. The `waitUntil` and `openStandardImage` helpers are copied from `DevelopInspectorTests` deliberately — those are private to that class, and duplicating twenty lines beats widening a test helper's access to share it.

```swift
import XCTest
import CoreImage
@testable import LUTzyKit

/// Phase 2 Step 10b. The ship gate is "the inspector drives live re-render", which is a claim about
/// wiring, so this drives `FakeRenderEngine` and asserts on the requests it recorded. The pure-value
/// half of the step is in `AdjustmentControlTests`.
@MainActor
final class AdjustInspectorTests: TempDirectoryTestCase {

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

    // MARK: - Reading

    /// An untouched panel reads its neutrals and writes nothing. The document must still be empty.
    func testAnUntouchedPanelLeavesTheDocumentEmpty() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        for control in AdjustmentControl.allCases {
            _ = viewModel.adjustmentValue(for: control)
        }
        XCTAssertEqual(viewModel.document.adjustments, [], "reading must never write")
        XCTAssertFalse(viewModel.hasAdjustments)
    }

    /// The value a control reads is in **slider space** — mapped, not the raw stored value.
    func testTemperatureReadsBackInSliderSpace() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .temperature).wrappedValue = 9000

        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), 9000, accuracy: 1e-9,
                       "what the slider was set to is what it must read back")
        XCTAssertEqual(AdjustmentControl.temperature.value(in: viewModel.document.adjustments),
                       4000, accuracy: 1e-9,
                       "the node stores the reflected value, not the slider's")
    }

    // MARK: - Writing drives a render

    /// **The ship gate.** A slider write must reach the engine.
    func testAnAdjustmentEditRendersThroughTheEngine() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5

        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 1.5)],
                       "the document updates immediately, even though the render is debounced")

        try await waitUntil("the adjusted render") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 1.5)] }
        }
    }

    /// Resets are undebounced, per `updateDocument(debounced:)`'s contract — a button that lagged
    /// 60 ms would feel broken.
    func testResettingOneControlPreservesTheOthers() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .contrast).wrappedValue = 1.4
        viewModel.adjustmentBinding(for: .saturation).wrappedValue = 0.5
        viewModel.resetAdjustment(.contrast)

        XCTAssertEqual(viewModel.adjustmentValue(for: .contrast),
                       AdjustmentControl.contrast.neutral, accuracy: 1e-12)
        XCTAssertEqual(viewModel.adjustmentValue(for: .saturation), 0.5, accuracy: 1e-12)
    }

    func testResetAllEmptiesTheArray() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        viewModel.adjustmentBinding(for: .vibrance).wrappedValue = 0.4
        XCTAssertTrue(viewModel.hasAdjustments)

        viewModel.resetAllAdjustments()

        XCTAssertEqual(viewModel.document.adjustments, [])
        XCTAssertFalse(viewModel.hasAdjustments)
    }

    /// Reset-all must not touch the develop settings or the LUT — it is one panel's button.
    func testResetAllLeavesDevelopAndTheLUTAlone() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.updateDocument { $0.rawDevelop.exposure = 0.7 }
        viewModel.selectLUT(TestImages.warmLUT())
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5

        viewModel.resetAllAdjustments()

        XCTAssertEqual(viewModel.document.adjustments, [])
        XCTAssertEqual(viewModel.document.rawDevelop.exposure, 0.7, "develop is a different panel")
        XCTAssertNotNil(viewModel.document.lut.lutID, "the LUT is a different panel again")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AdjustInspectorTests 2>&1 | tail -20`
Expected: FAIL — `has no member 'adjustmentValue'`.

- [ ] **Step 3: Write the implementation**

Create `Sources/LUTzyKit/ViewModels/AppViewModel+Adjust.swift`:

```swift
import SwiftUI

/// `AppViewModel`'s adjustment bindings — Step 10b.
///
/// Deliberately thin. Every one of these forwards to a pure function on `AdjustmentControl` and then
/// re-renders; none of them knows how the sparse array is shaped. That is what lets the whole
/// contract be tested without a view model, an engine or a GPU — see `AdjustmentControlTests`.
extension AppViewModel {

    /// What a row should display, in **slider space**.
    ///
    /// **Reading never writes**, the same property `developBinding(for:)` has: an absent node reads
    /// as the control's neutral rather than being seeded into the document. Seeding on open would
    /// make every document non-neutral the moment the panel was looked at, which would in turn make
    /// the A/B comparison offer itself on an untouched image.
    func adjustmentValue(for control: AdjustmentControl) -> Double {
        control.sliderMapped(control.value(in: document.adjustments))
    }

    /// A two-way binding for one row. Slider space on both sides — `sliderMapped` is self-inverse,
    /// so the same call converts each way.
    ///
    /// **Debounced**, because every row here is a continuous control: there are no toggles in this
    /// panel, unlike Develop's three.
    func adjustmentBinding(for control: AdjustmentControl) -> Binding<Double> {
        Binding(
            get: { self.adjustmentValue(for: control) },
            set: { newValue in
                self.updateDocument(debounced: true) { document in
                    document.adjustments = control.setting(
                        control.sliderMapped(newValue), in: document.adjustments
                    )
                }
            }
        )
    }

    /// Return one row to its neutral. Undebounced — `updateDocument(debounced:)`'s contract is that
    /// discrete controls fire immediately.
    func resetAdjustment(_ control: AdjustmentControl) {
        updateDocument { document in
            document.adjustments = control.setting(control.neutral, in: document.adjustments)
        }
    }

    /// Return every row to its neutral.
    ///
    /// Clears `adjustments` and nothing else: `rawDevelop` and the LUT belong to other panels, and a
    /// Reset button that reached across panel boundaries would be a trap.
    func resetAllAdjustments() {
        updateDocument { $0.adjustments = [] }
    }

    /// Whether any row is off its neutral — the Reset button's enabled state.
    ///
    /// Reads the array's emptiness rather than comparing nine values, which is only correct because
    /// the array is sparse: an identity node never survives a write. `AdjustmentControlTests`
    /// pins that.
    var hasAdjustments: Bool { !document.adjustments.isEmpty }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter AdjustInspectorTests 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Run the whole suite and commit**

Run: `swift build && swift test 2>&1 | tail -3`
Expected: green.

```bash
git add Sources/LUTzyKit/ViewModels/AppViewModel+Adjust.swift Tests/LUTzyKitTests/AdjustInspectorTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10b: adjustment view-model bindings

Four forwarding methods over AdjustmentControl's pure functions. Reading
never writes — an absent node reads as its control's neutral rather than
being seeded, so looking at the panel cannot make a document non-neutral.

Sliders are debounced and resets are not, per updateDocument's contract.
Every row here is continuous; unlike Develop there are no toggles.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: The panel

**Files:**
- Create: `Sources/LUTzyKit/Views/AdjustInspectorView.swift`
- Modify: `Sources/LUTzyKit/ViewModels/AppViewModel.swift` (`InspectorTab`, around line 152)
- Modify: `Sources/LUTzyKit/Views/InfoInspectorView.swift` (the `switch` at line 20)
- Modify: `Tests/LUTzyKitTests/AdjustInspectorTests.swift`

**Interfaces:**
- Consumes: everything from Task 6.
- Produces: `AppViewModel.InspectorTab.adjust`; `struct AdjustInspectorView`.

- [ ] **Step 1: Write the failing test**

Append to `AdjustInspectorTests.swift`:

```swift
// MARK: - The tab

extension AdjustInspectorTests {

    /// Three tabs, in pipeline order left to right.
    func testTheInspectorHasThreeTabsInPipelineOrder() {
        XCTAssertEqual(AppViewModel.InspectorTab.allCases, [.info, .develop, .adjust])
        XCTAssertEqual(AppViewModel.InspectorTab.adjust.title, "Adjust")
    }

    /// The histogram is gated on the Info tab being on screen. Adjust is as much "a panel nobody is
    /// looking at" as Develop is, so switching to it must not start tallying pixels — the same
    /// finding `testTheDevelopTabDoesNotTallyAHistogram` pins for the other tab.
    func testTheAdjustTabDoesNotTallyAHistogram() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        viewModel.isInspectorPresented = true
        viewModel.inspectorTab = .adjust
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        try await Task.sleep(for: .milliseconds(300))

        let requests = await fake.histogramRequests
        XCTAssertTrue(requests.isEmpty,
                      "the Adjust tab has no histogram; \(requests.count) tallies were issued")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AdjustInspectorTests 2>&1 | tail -20`
Expected: FAIL — `type 'AppViewModel.InspectorTab' has no member 'adjust'`.

- [ ] **Step 3: Add the tab case**

In `Sources/LUTzyKit/ViewModels/AppViewModel.swift`, extend the enum at line 152. The `didSet` on `inspectorTab` above it already reads `if inspectorTab == .info`, so the histogram stays correctly gated with no change:

```swift
    enum InspectorTab: String, CaseIterable, Sendable {
        case info, develop, adjust
        var title: String {
            switch self {
            case .info: return "Info"
            case .develop: return "Develop"
            case .adjust: return "Adjust"
            }
        }
    }
```

- [ ] **Step 4: Write the panel**

Create `Sources/LUTzyKit/Views/AdjustInspectorView.swift`:

```swift
import SwiftUI

/// Tone and colour adjustments — the nodes that run *after* the develop stage and *before* the LUT.
///
/// **One state, where `DevelopInspectorView` has three.** That asymmetry is the honest one: Develop's
/// three states exist because *the file* answers a question — is there a decode stage, and has the
/// capability probe landed yet — and here there is no question to ask. Adjustments are applied to an
/// already-developed image, so they mean the same thing for a RAW and a JPEG, and no row is ever
/// absent or gated.
///
/// Nine rows over five `AdjustmentNode` cases, one row per parameter. The list is not written out
/// here — it comes from `AdjustmentControl.allCases`, so which rows appear and in what order is a
/// value the tests can assert rather than a shape buried in a `ViewBuilder`.
struct AdjustInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(AdjustmentControl.allCases, id: \.self) { control in
                    controlRow(control)
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack {
            Text("Adjustments").font(.headline)
            Spacer()
            Button("Reset") { viewModel.resetAllAdjustments() }
                .buttonStyle(.link)
                .disabled(!viewModel.hasAdjustments)
        }
    }

    @ViewBuilder
    private func controlRow(_ control: AdjustmentControl) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(control.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(readout(for: control))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.resetAdjustment(control)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Reset to neutral")
            }

            Slider(value: viewModel.adjustmentBinding(for: control), in: control.range)
        }
    }

    /// Kelvin reads as a whole number; everything else to two places. 5842.20 K is noise on a
    /// slider whose useful travel is thousands of degrees wide.
    private func readout(for control: AdjustmentControl) -> String {
        let value = viewModel.adjustmentValue(for: control)
        switch control {
        case .temperature:
            return String(format: "%.0f K", value)
        case .exposure, .brightness, .contrast, .saturation, .highlights, .shadows, .tint, .vibrance:
            return String(format: "%.2f", value)
        }
    }
}
```

- [ ] **Step 5: Wire it into the inspector**

In `Sources/LUTzyKit/Views/InfoInspectorView.swift`, extend the `switch` at line 20:

```swift
                switch viewModel.inspectorTab {
                case .info:
                    infoContent
                case .develop:
                    DevelopInspectorView(viewModel: viewModel)
                case .adjust:
                    AdjustInspectorView(viewModel: viewModel)
                }
```

No change is needed to `tabSwitcher` — it already iterates `InspectorTab.allCases`.

- [ ] **Step 6: Run to verify it passes**

Run: `swift build && swift test --filter AdjustInspectorTests 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 7: Look at it**

Run: `swift run`

Open an image, press ⌘I, click **Adjust**. Confirm: nine rows in the order Exposure, Brightness, Contrast, Saturation, Highlights, Shadows, Temperature, Tint, Vibrance; the preview moves as each slider is dragged; the Highlights slider starts hard right and only travels left; dragging Temperature right makes the picture **warmer**; Reset is disabled until something moves; each row's reset chevron returns just that row. If any of that is wrong, stop and report before committing.

- [ ] **Step 8: Run the whole suite and commit**

Run: `swift test 2>&1 | tail -3`
Expected: green.

```bash
git add Sources/LUTzyKit/Views/AdjustInspectorView.swift Sources/LUTzyKit/Views/InfoInspectorView.swift Sources/LUTzyKit/ViewModels/AppViewModel.swift Tests/LUTzyKitTests/AdjustInspectorTests.swift
git commit -m "$(cat <<'EOF'
Phase 2 Step 10b: the adjust panel

Nine rows from AdjustmentControl.allCases, so the layout is a value the
tests can assert rather than a shape buried in a ViewBuilder. Tabs now
read Info | Develop | Adjust, left to right in pipeline order.

One state, where the develop panel has three. Develop's states exist
because the file answers a question — is there a decode stage, has the
probe landed — and adjustments have no such question: they apply to an
already-developed image, so no row is ever absent or gated.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Pin the one-render property

An adjustment edit costs **one** render, not two: `originalForComparison` strips adjustments, so the A/B baseline genuinely does not move. This already works — `pendingDevelopChange` stays false — which is exactly why it needs a test. Nothing would notice if a later edit started re-rendering the baseline on every slider tick.

**Files:**
- Modify: `Tests/LUTzyKitTests/AdjustInspectorTests.swift`

**Interfaces:**
- Consumes: everything from Task 6. No production code changes in this task.

- [ ] **Step 1: Write the test**

Append to `AdjustInspectorTests.swift`:

```swift
// MARK: - Render cost

extension AdjustInspectorTests {

    /// **An adjustment edit costs one render; a develop edit costs two.**
    ///
    /// `EditDocument.originalForComparison` keeps `rawDevelop` and strips `adjustments` (§8.5), so
    /// the comparison baseline moves when develop moves and stays put when an adjustment moves.
    /// That falls out of `pendingDevelopChange` never being set here, which is to say it works by
    /// accident of the current code — hence this test. Without it, a later edit that started
    /// scheduling the baseline unconditionally would double every slider tick's cost silently.
    func testAnAdjustmentEditDoesNotReRenderTheComparisonBaseline() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        // Let the opening renders settle so the count below is only this edit's.
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        try await Task.sleep(for: .milliseconds(200))
        let before = await fake.previewRequests.count

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        try await waitUntil("the adjusted render") {
            await fake.previewRequests.contains { $0.document.adjustments == [.exposure(ev: 1.5)] }
        }
        try await Task.sleep(for: .milliseconds(200))   // a second render would have landed by now

        let after = await fake.previewRequests.count
        XCTAssertEqual(after - before, 1,
                       "an adjustment must schedule the preview and nothing else; the A/B baseline "
                       + "strips adjustments, so it cannot have moved")
    }

    /// The other half of the same claim, so the test above cannot pass by the renderer being broken:
    /// a **develop** edit must still cost two.
    func testADevelopEditStillReRendersTheComparisonBaseline() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        try await Task.sleep(for: .milliseconds(200))
        let before = await fake.previewRequests.count

        viewModel.updateDocument { $0.rawDevelop.exposure = 0.7 }
        try await Task.sleep(for: .milliseconds(300))

        let after = await fake.previewRequests.count
        XCTAssertEqual(after - before, 2,
                       "a develop edit moves the baseline too — preview plus baseline")
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter AdjustInspectorTests 2>&1 | tail -20`
Expected: PASS both. These characterize existing behavior, so they should pass without any production change.

**If `testADevelopEditStillReRendersTheComparisonBaseline` fails with 1 instead of 2**, the baseline is not being scheduled for develop edits — that is a real regression in Step 10a's behavior, not a bad test. Stop and report it rather than adjusting the expected number.

- [ ] **Step 3: Commit**

```bash
git add Tests/LUTzyKitTests/AdjustInspectorTests.swift
git commit -m "$(cat <<'EOF'
Pin the adjust panel's one-render-per-edit property

An adjustment edit schedules the preview and nothing else, because
originalForComparison strips adjustments and so the A/B baseline cannot
have moved. A develop edit still costs two. Both halves are asserted, so
the first cannot pass by the renderer being broken.

This already worked — which is the reason to pin it. Nothing else would
notice a later edit that started scheduling the baseline unconditionally
and doubled the cost of every slider tick.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: The A/B gate

Side-by-side and Space-hold are gated on `selectedLUT != nil`. With the Adjust panel shipped, pushing exposure +2 with no LUT gives no comparison at all — the V key and Space both do nothing. §8.5 flagged this as open; 10b forces it.

**Files:**
- Modify: `Sources/LUTzyKit/ViewModels/AppViewModel.swift` (add `isComparisonAvailable`)
- Modify: `Sources/LUTzyKit/Views/PreviewView.swift` (lines 15 and 94)
- Modify: `Tests/LUTzyKitTests/AdjustInspectorTests.swift`

**Interfaces:**
- Consumes: `AppViewModel.document`, `EditDocument.originalForComparison`.
- Produces: `var AppViewModel.isComparisonAvailable: Bool`.

- [ ] **Step 1: Write the failing test**

Append to `AdjustInspectorTests.swift`:

```swift
// MARK: - The A/B gate

extension AdjustInspectorTests {

    /// **§8.5, forced by this step.** Comparison used to be gated on `selectedLUT != nil`, which was
    /// defensible while a LUT was the only thing that could change the picture. The Adjust panel
    /// makes it wrong: an image with exposure pushed two stops and no LUT selected had a dead V key
    /// and a dead Space bar.
    ///
    /// The gate is now "does the document differ from its own comparison baseline", which is exactly
    /// the set of edits the split view would show a difference for — and, unlike enumerating the
    /// look-bearing fields, it stays correct the next time the document grows one.
    func testComparisonBecomesAvailableWithAnAdjustmentAndNoLUT() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        XCTAssertFalse(viewModel.isComparisonAvailable, "an untouched image has nothing to compare")

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 2.0

        XCTAssertNil(viewModel.selectedLUT, "no LUT — this is the case the old gate got wrong")
        XCTAssertTrue(viewModel.isComparisonAvailable)
    }

    /// The old behaviour must survive: a LUT alone still offers comparison.
    func testComparisonIsStillAvailableWithALUTAndNoAdjustments() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.selectLUT(TestImages.warmLUT())

        XCTAssertEqual(viewModel.document.adjustments, [])
        XCTAssertTrue(viewModel.isComparisonAvailable)
    }

    /// A **develop-only** edit must not offer comparison, because the baseline keeps `rawDevelop`
    /// (§8.5) — both sides would render identically, and a split view showing two identical
    /// pictures is worse than no split view.
    func testADevelopOnlyEditDoesNotOfferComparison() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.updateDocument { $0.rawDevelop.exposure = 0.7 }

        XCTAssertFalse(viewModel.isComparisonAvailable,
                       "the baseline keeps rawDevelop, so both halves would be the same picture")
    }

    /// Undoing the edit by hand withdraws the offer again — the sparse array is what makes this work.
    func testComparisonWithdrawsWhenTheAdjustmentReturnsToNeutral() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 2.0
        XCTAssertTrue(viewModel.isComparisonAvailable)

        viewModel.resetAdjustment(.exposure)
        XCTAssertFalse(viewModel.isComparisonAvailable)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AdjustInspectorTests 2>&1 | tail -20`
Expected: FAIL — `has no member 'isComparisonAvailable'`.

- [ ] **Step 3: Add the property**

In `Sources/LUTzyKit/ViewModels/AppViewModel.swift`, next to `selectedLUT` (around line 125):

```swift
    /// Whether the A/B comparison has anything to show.
    ///
    /// **Not `selectedLUT != nil`**, which is what this was until Step 10b. That was defensible while
    /// a LUT was the only thing that could change the picture; the Adjust panel made it wrong, and an
    /// image with exposure pushed two stops and no LUT had a dead V key and a dead Space bar (§8.5).
    ///
    /// Comparing the document against its own baseline rather than enumerating the look-bearing
    /// fields is deliberate: it is exactly the set of edits the split view would show a difference
    /// for, and it stays correct the next time the document grows a field. Note that a develop-only
    /// edit correctly reads `false` — `originalForComparison` keeps `rawDevelop`, so both halves
    /// would be the same picture.
    var isComparisonAvailable: Bool { document != document.originalForComparison }
```

- [ ] **Step 4: Use it in the view**

In `Sources/LUTzyKit/Views/PreviewView.swift`, replace both occurrences of `viewModel.selectedLUT != nil` (lines 15 and 94) with `viewModel.isComparisonAvailable`.

Run: `grep -n "selectedLUT != nil" Sources/LUTzyKit/Views/PreviewView.swift`
Expected: no output — both are gone.

- [ ] **Step 5: Run to verify it passes**

Run: `swift build && swift test --filter AdjustInspectorTests 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 6: Run the whole suite**

Run: `swift test 2>&1 | tail -3`
Expected: green. If an existing test asserted the old LUT-only gate, read it before changing it — if it was pinning `selectedLUT != nil` as the *rule*, update it to the new rule and say so in the commit; if it was pinning comparison working *with a LUT*, it should still pass untouched.

- [ ] **Step 7: Check it by hand**

Run: `swift run`

Open an image, select no LUT, push Exposure to +2 in the Adjust tab. The side-by-side split must appear and Space must show the unadjusted image.

- [ ] **Step 8: Commit**

```bash
git add Sources/LUTzyKit/ViewModels/AppViewModel.swift Sources/LUTzyKit/Views/PreviewView.swift Tests/LUTzyKitTests/AdjustInspectorTests.swift
git commit -m "$(cat <<'EOF'
Gate A/B on a non-neutral document, not on a LUT

PHASE2_SPEC.md §8.5 left this open; the adjust panel forces it. An image
with exposure pushed two stops and no LUT selected had a dead V key and a
dead Space bar, because comparison was gated on selectedLUT != nil.

The gate is now "the document differs from its own comparison baseline",
which is exactly the set of edits the split view would show a difference
for. A develop-only edit still reads false, correctly — the baseline keeps
rawDevelop, so both halves would be the same picture.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Close the spec's open questions

**Files:**
- Modify: `docs/PHASE2_SPEC.md` (§2 baseline table, §6 migration table row 10b, §8.5, §8.6, §8.7)

**Interfaces:**
- Consumes: the measured outcomes of Tasks 2, 5 and 9.
- Produces: documentation only. No code, no tests.

- [ ] **Step 1: Update the §6 migration table**

Strike through the 10b row in the established style, and record what the step actually cost and found. Follow the 10a row's format exactly — it names the measured numbers and the caveat, not just "done".

- [ ] **Step 2: Update the §2 baseline table**

The last row reads `| ❌ No RAW develop UI, no undo | Steps 10–11 |`. Step 10a already made half of that stale and 10b makes the rest. Change it to record that both inspectors ship and only undo is outstanding.

- [ ] **Step 3: Close §8.6**

Mark it decided — fixed slots, not duplicates — and say why the recommendation was overturned: nine per-parameter rows over five nodes is a usable panel in one step, a stacking editor needs add/remove/reorder UI and list identity for an enum that is not `Identifiable`, and the model still permits duplicates so nothing is foreclosed.

- [ ] **Step 4: Close §8.5's remaining half**

The "still open" sentence about whether side-by-side triggers on any non-neutral document is now answered. Record the answer, that `isComparisonAvailable` implements it, and the one non-obvious consequence: a develop-only edit does not offer comparison, because the baseline keeps `rawDevelop`.

- [ ] **Step 5: Close §8.7**

Add Task 2's measurement of `CIRAWFilter.neutralTemperature` beside the existing `CITemperatureAndTint` table, and record the resolution: the node's direction is unchanged and still pinned by `testRaisingKelvinCoolsTheImage`; the Adjust slider reflects about D65 in `AdjustmentControl.sliderMapped`; the slider range is 2000…11000 because the reflection has to be closed.

- [ ] **Step 6: Add §9 facts worth not re-litigating**

Append to the "**This codebase:**" list in §9:

- `CIFilterBuiltins.h` documents no parameter ranges — only prose. Ranges live in the runtime `CIFilter.attributes` dictionary.
- `CIHighlightShadowAdjust.inputHighlightAmount` has a slider floor of **0.3** and an identity of **1**, at the range maximum.
- `CIHighlightShadowAdjust` has a third parameter, `radius`, which is pixel-sized and would violate §5 if set. Its default and identity are both **0**, and `RenderPipeline` never touches it.

- [ ] **Step 7: Check the spec still reads as a distillation**

Run: `wc -l docs/PHASE2_SPEC.md`

`CLAUDE.md` is explicit that this file is a distillation and per-component transcripts belong in the PR. If this task added more than ~60 lines, cut it back — record the decisions and the measurements, not the reasoning that got there.

- [ ] **Step 8: Commit**

```bash
git add docs/PHASE2_SPEC.md
git commit -m "$(cat <<'EOF'
Close the three open questions Step 10b settled

§8.6 recommended duplicate adjustment nodes and §6's own 10b row said
fixed slots; fixed slots won. §8.5's remaining half — whether side-by-side
triggers on any non-neutral document — is answered by isComparisonAvailable.
§8.7's Kelvin direction is resolved by measuring the other knob and
reflecting the adjust slider rather than changing either filter's wiring.

Also records three CIFilter facts worth not re-deriving, including the
one that mattered: highlightAmount's identity sits at its range maximum.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Ship it

**Files:** none.

- [ ] **Step 1: Full verification from clean**

```bash
swift build 2>&1 | tail -5 && swift test 2>&1 | tail -5
```

Expected: builds with zero warnings; the suite is green. Record the new test count.

- [ ] **Step 2: Confirm the Swift 6 promise still holds**

Run: `grep -rn "@unchecked Sendable\|nonisolated(unsafe)\|@preconcurrency" Sources/`
Expected: no output. (`PackageSettingsTests` also asserts this, but check by hand — that test is the thing most likely to have been "fixed" by mistake.)

- [ ] **Step 3: Confirm nothing load-bearing was modified**

Run: `git diff --stat main -- Sources/LUTzyKit/Models/AdjustmentNode.swift Sources/LUTzyKit/Models/RenderPipeline.swift Sources/LUTzyKit/Models/RenderEngine.swift Sources/LUTzyKit/Models/EditDocument.swift`
Expected: **no output.** The panel was supposed to be purely additive; if any of these four moved, the design was wrong somewhere and it needs to be raised, not merged.

- [ ] **Step 4: Confirm the tree is clean**

Run: `git status --porcelain`
Expected: empty.

- [ ] **Step 5: Open the PR**

```bash
git push -u origin feature/phase2-adjustments-inspector
gh pr create --title "Phase 2 Step 10b: adjustments inspector" --body "$(cat <<'EOF'
Nine per-parameter rows over the five `AdjustmentNode` cases, driving
`EditDocument.adjustments` live. The array has existed since Step 2 and been
folded by the pipeline since Step 3; nothing in the running app has ever
written to it until now.

Purely additive: `AdjustmentNode`, `RenderPipeline`, `RenderEngine` and
`EditDocument` are untouched, which is the check on whether the design was
right.

Closes three questions `PHASE2_SPEC.md` had carried open:

- **§8.6** recommended duplicate nodes; §6's own 10b row said fixed slots. Fixed
  slots won. The model still permits stacking, so a list editor stays possible
  without a migration.
- **§8.5** — comparison is now gated on the document differing from its own
  baseline, not on a LUT being set. Without this the panel would have shipped
  with a dead V key on any un-LUT'd image.
- **§8.7** — resolved by measuring the *other* Kelvin knob. `CIRAWFilter`'s runs
  the photographic way round, the node's runs backwards, so the adjust slider
  reflects about D65 and neither filter's wiring changed.

Ranges were probed off the runtime `CIFilter.attributes` dictionary rather than
guessed — the headers document none. That turned up `inputHighlightAmount`'s
floor of 0.3 with its identity at the range *maximum*, so the Highlights slider
travels one way only, and confirmed `CIHighlightShadowAdjust.radius` — the one
pixel-sized parameter in the whole node set — defaults to 0 and is never set, so
§5's resolution-independence invariant holds.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 6: Report the PR URL to the user.**
