# Phase 2 Step 10b — Adjustments inspector

**Ship gate:** the inspector drives a live re-render.

Step 10a gave the RAW decoder a UI. Step 10b gives the same treatment to the five `AdjustmentNode`
cases, which have existed since Step 2, have been folded by `RenderPipeline.applyAdjustments` since
Step 3, and which **nothing in the running app has ever written**. `document.adjustments` is `[]` in
every session that has ever shipped. This step is the first thing to put a value in it.

The panel is purely additive: `AdjustmentNode`, `RenderPipeline`, `RenderEngine` and `EditDocument`
are untouched. That is what Steps 2–6 bought, and it is the check on whether this design is right —
if it needs to reach into the pipeline, it is wrong.

---

## 1. Decisions taken

| Question | Decision | Was |
|---|---|---|
| List semantics | **Fixed slots**, one node per case, canonical pipeline order | §8.6 recommended duplicates; §6's 10b row said fixed slots. Fixed slots wins; §8.6 gets amended. |
| Backing store | **Sparse** — the array holds only non-identity nodes | — |
| Row granularity | **Nine per-parameter rows**, not five per-node rows | — |
| Kelvin direction | Both Kelvin sliders in the inspector must agree; measure Develop's first | §8.7, open since Step 3 |
| A/B gate | Gate on a **non-neutral document**, not on `selectedLUT != nil` | §8.5, "still open" |

`AdjustmentNode` keeps allowing duplicates *in the model* — its doc comment's "the array is a
pipeline, not a set of slots" stays true. Only the UI is one-of-each. A stacking editor can be built
later without a model migration, which is the whole reason to leave the model alone.

---

## 2. What gets built

**New — `Sources/LUTzyKit/Models/AdjustmentControl.swift`.** The `DevelopControl` analogue: nine
cases, declaration order = layout order = canonical pipeline order. **Canonical order is
`AdjustmentNode`'s own case-declaration order** — exposure, colorControls, highlightShadow,
temperatureTint, vibrance — which is what §3 of `PHASE2_SPEC.md` shows and what `applyAdjustments`
folds; the nine controls are that order with the multi-parameter nodes expanded in place. Carries
`title`, `range` and
`neutral`, plus the two functions that hold all of the real logic:

```swift
func value(in adjustments: [AdjustmentNode]) -> Double
func setting(_ value: Double, in adjustments: [AdjustmentNode]) -> [AdjustmentNode]
```

Pure functions over values — no view model, no `CIContext`, no image, no RAW. The entire sparse
contract is therefore assertable on CI, which has neither a GPU-backed fixture nor a DNG. This is
also why the logic does **not** live on `AppViewModel`: that file is 1004 lines before this step.

**New — `Sources/LUTzyKit/Views/AdjustInspectorView.swift`.** A flat `ForEach` over
`AdjustmentControl.allCases` with the same row shape as `DevelopInspectorView` — title, monospaced
readout, reset chevron, slider. One state, no `switch`; see §6.

**New — `Tests/LUTzyKitTests/AdjustInspectorTests.swift`.** See §7.

**Changed:**

- `AppViewModel` — `InspectorTab` gains `.adjust`, plus four methods that do nothing but forward to
  §3's pure functions and re-render: `adjustmentValue(for:)`, `adjustmentBinding(for:)`,
  `resetAdjustment(_:)`, `resetAllAdjustments()`.
- `InfoInspectorView` — a third segment.
- `PreviewView` — the A/B gate, two call sites (`:15` and `:94`).
- `docs/PHASE2_SPEC.md` — §6's 10b row, and the §8.5/§8.6/§8.7 open questions this step closes.

**Also, as its own commit before the feature work:** split `AppViewModel` into
`AppViewModel+Develop.swift` and `AppViewModel+Adjust.swift`. Pure code motion for the develop half,
so 10b's real diff stays readable rather than arriving as +80 lines inside a four-figure file.

---

## 3. The sparse contract

Set contrast to 1.4 and `.colorControls(brightness: 0, contrast: 1.4, saturation: 1)` appears at
index 1. Reset it and the node vanishes, because its siblings were already at their identity values.
The rule is one sentence: **build the updated node, then insert it at its canonical index or remove
it, according to `isIdentity`.**

The invariants, which are also the tests:

- Reading a control whose node is absent returns that control's `neutral`.
- Writing `neutral` into the last non-neutral parameter of a node removes the node.
- Writing a non-neutral value into an absent node inserts at the **canonical index**, not the end.
- The array is always sorted in canonical order and free of duplicates.
- `control.setting(v, in: a).value(in:) == v` for every control and any in-range `v`.
- Writing one parameter preserves its siblings.

Sparseness is what keeps `EditDocument() == []` true, which in turn keeps §5's "empty document is
identity" invariant and `originalForComparison` (which sets `adjustments: []`) meaning what they say.
It also keeps Step 11's undo snapshots small.

---

## 4. Ranges and neutrals — measured, not guessed

The `CIFilterBuiltins.h` headers document **no ranges at all**, only prose descriptions. The numbers
live in the runtime `CIFilter.attributes` dictionary, which was probed directly on the macOS 26 SDK
rather than copied from memory:

| Control | Node parameter | Identity | Filter's slider range | Ours |
|---|---|---|---|---|
| Exposure | `exposure(ev:)` | 0 | −10…10 | **−4…4** |
| Brightness | `colorControls.brightness` | 0 | −1…1 | −1…1 |
| Contrast | `colorControls.contrast` | 1 | 0.25…4 | 0.25…4 |
| Saturation | `colorControls.saturation` | 1 | 0…2 | 0…2 |
| Highlights | `highlightShadow.highlights` | 1 | **0.3…1** | 0.3…1 |
| Shadows | `highlightShadow.shadows` | 0 | −1…1 | −1…1 |
| Temperature | `temperatureTint.temp` | 6500 | *(none — a `CIVector`)* | **2000…11000 K** |
| Tint | `temperatureTint.tint` | 0 | *(none)* | −150…150 |
| Vibrance | `vibrance(amount:)` | 0 | −1…1 | −1…1 |

Every `neutral` above equals the value `AdjustmentNode.isIdentity` already names, and every one is
also the filter's own documented `kCIAttributeIdentity`. A test loops all nine rather than spelling
them twice, so a tenth control cannot ship with a neutral that disagrees with the model.

Three rows need their reasoning recorded, because each is a place a later reader would otherwise
assume a mistake:

**Exposure is narrowed to −4…4, deliberately.** The filter accepts −10…10. `DevelopControl.exposure`
is −4…4 — a UI throw chosen in 10a, not a framework limit — and two exposure sliders one tab apart
with different travel is worse than either range on its own. Widen both together or neither.

**Highlights runs 0.3…1, and its identity is at the maximum.** This is the filter's own floor, not a
choice. The slider therefore travels in one direction only: down, recovering highlights. It is also
the one documented exception to 10a's `testEveryPerImageSeedLandsStrictlyInsideItsSliderRange` check
— an identity *at* a boundary is correct here, and the Adjust equivalent of that test must assert
"inside or at a filter-defined boundary" and name this row as the reason.

**Temperature is 2000…11000 K, narrower than Develop's 2000…50000.** See §5 — the range is forced by
the inversion, not chosen for taste.

**One thing checked rather than assumed:** `CIHighlightShadowAdjust` has a third property, `radius`,
which is pixel-sized and would violate §5's resolution-independence invariant if it were ever set —
an early-downscaled preview and a full-resolution export would diverge silently, exactly the failure
§5 warns about. It defaults to **0**, its identity is **0**, and `RenderPipeline.filter(for:input:)`
never touches it (`RenderPipeline.swift:180`). The invariant holds. No node in the set carries a
pixel-sized parameter, and the panel must not introduce one.

---

## 5. The Kelvin problem

§8.7 measured, back in Step 3, that the adjustment node's Kelvin runs backwards from every photo
app: with `neutral` pinned at D65 and only `targetNeutral` moving, 3200 K **warms** and 9000 K
**cools**. `testRaisingKelvinCoolsTheImage` pins it.

Until 10b that was academic. Now the Adjust tab sits one segment from a Develop tab that already
ships a "White Balance" Kelvin slider, and two Kelvin sliders that disagree in one inspector is not a
defensible thing to ship.

**The requirement is agreement, and the direction is measured, not assumed.** The first task of the
implementation measures `CIRAWFilter.neutralTemperature`'s direction on the real DNG — a printing
test in the shape of `RAWCapabilitiesTests.testProbingARealRAWReportsItsDecodersSeeds`, which
`XCTSkip`s on CI. If Develop turns out to follow the photographic convention (right = warmer, which
is what a *source illuminant* assumption should do, but has never been measured in this repo), the
Adjust binding inverts to match. If it does not, neither inverts and both are labelled honestly.

**The obvious inversion is wrong, and this is the trap worth naming.** Reflecting about D65 —
`targetNeutral = 13000 − sliderK` — maps Develop's 2000…50000 onto 11000…**−37000**. Negative Kelvin
is not a colour. So the Adjust temperature slider is **2000…11000 K**, symmetric about 6500, which
makes the reflection a closed involution over its own range with no clamping and no dead zone. It is
also the more useful photographic throw; Develop's 2000…50000 is `CIRAWFilter`'s documented bound,
which is a limit rather than a recommendation.

The mapping lives in `AdjustmentControl` as a pure function with a round-trip test. `AdjustmentNode`,
`RenderPipeline` and `testRaisingKelvinCoolsTheImage` are all untouched — the model keeps storing
filter-native values, and only the binding maps. That is deliberate: it keeps the change reversible
in one function if a future decision goes the other way.

---

## 6. Availability, tabs, and render cost

The Adjust tab is live whenever **any** image is open, RAW or not. Adjustments sit after the develop
stage and are entirely source-kind agnostic, so there is no probe, no three-state, and no absent
rows. `AdjustInspectorView` has exactly one state. The asymmetry against `DevelopInspectorView`'s
three states is honest: Develop's states exist because *the file* answers a question, and here there
is no question to ask.

Tab order is **Info | Develop | Adjust** — pipeline order, left to right.

**Debounce** follows the existing contract unchanged: sliders `updateDocument(debounced: true)` at
60 ms, reset buttons `debounced: false`. There are no toggles in this panel.

**An adjustment edit costs one render, not two.** `pendingDevelopChange` stays false, so
`scheduleOriginalPreview()` is not called — `originalForComparison` strips adjustments by design
(§8.5), so the comparison baseline genuinely does not move. This falls out of the current code with
no change at all, which is exactly why it needs a test: nothing else would notice if a later edit
started re-rendering the baseline on every slider tick.

---

## 7. Testing

`AdjustInspectorTests.swift`, mirroring `DevelopInspectorTests.swift`. Everything below runs on CI
except the one Kelvin measurement, which `XCTSkip`s without a DNG — the same arrangement 10a shipped,
and the same caveat: a green tick on CI says nothing about that one.

- The six sparse-array invariants of §3, as pure-value tests.
- Every control's `neutral` equals the value `AdjustmentNode.isIdentity` names — looped, not spelled.
- Every `neutral` sits inside its range, or at a filter-defined boundary, with Highlights named as
  the sole boundary case.
- The temperature mapping round-trips, and its endpoints stay inside 2000…11000.
- Binding round-trip through `AppViewModel` against `FakeRenderEngine`.
- Resetting one control preserves its siblings; `resetAllAdjustments()` empties the array.
- An adjustment edit schedules **one** preview and **no** baseline render.
- The A/B gate: a document with an adjustment and no LUT enables comparison.
- Kelvin direction on a real DNG (`XCTSkip` on CI), recorded back into §8.7.

---

## 8. Out of scope

- **No add / remove / reorder.** Fixed slots is the decision; the model still permits stacking.
- **No reset-on-open.** Whether a document's adjustments survive stepping to the next image is the
  same question §8.4 defers to Step 11's `EditDocumentStore`, and it should be answered once, there,
  for `rawDevelop` and `adjustments` together — not twice, differently.
- **No undo.** Step 11.
- **No presets, no persistence.** §8.8 keeps v1 in-memory.
