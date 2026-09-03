---
id: LUMO-089
title: Reset adjustment controls by double-clicking their labels
type: task
status: done
priority: medium
labels:
  - mvp
  - ux
  - accessibility
created: 2026-09-01T14:35:34.852Z
updated: 2026-09-01T16:04:24.228Z
order: a0
board: product
commits:
  - 14ec468
---

## Objective

Make double-clicking an adjustment label reset that control to its neutral/default value, and remove
the need for a persistent reset icon in every row.

## Context

Light already has a partial double-click reset treatment, while Color, Develop, Effects, and the
legacy Adjust rows still expose small reset buttons or inconsistent behavior. The interaction
should be consistent for controls such as Vibrance, Tint, Shadows, and per-zone/per-channel rows,
without making a single click unexpectedly mutate a value.

## Acceptance criteria

- [ ] Double-clicking the visible label of every resettable Light, Develop, Color, Effects, and
  remaining adjustment row resets only that control and updates the preview before mouse-up where
  the existing interaction contract requires it.
- [ ] Reset icons are removed from rows covered by the new interaction; section/panel reset actions
  remain available where useful.
- [ ] A single click, slider drag, and text-field edit retain their current behavior and do not
  accidentally reset the control.
- [ ] Reset gestures coalesce into sensible undo entries and work for repeated channel/zone labels
  with contextual accessibility names.
- [ ] Provide a keyboard/VoiceOver-accessible reset action because double-click is not sufficient as
  the only input path.
- [ ] Add coverage for representative controls across each inspector and confirm neutral values.

## Implementation notes

Relevant code includes `LightInspectorView.swift`, `DevelopInspectorView.swift`,
`AdjustInspectorView.swift`, `ColorInspectorView.swift`/`ColorValueRow`, and
`EffectsInspectorView.swift`. Centralize the row interaction if possible so future controls inherit
the same reset semantics.

### Comment — codex @ 2026-09-01T16:02:20.676Z

Implemented and verified in commit 14ec468. Adjustment row labels now reset their control on double-click across Light, Develop, Adjust, Color, and Effects; row reset icons were removed while section actions remain. Added contextual accessibility reset actions, immediate preview/reset cancellation, undo-group boundaries, and representative neutral-value coverage. Validation: swift test — 510 passed, 26 expected skips, 0 failures.

### Comment — claude @ 2026-09-01T16:04:21.614Z

## Verification report — counterpoint agent (claude/sonnet)

Reviewed commit 14ec468 against all six acceptance criteria.

- **Double-click reset on labels**: New `ResettableAdjustmentLabel` (Sources/LumoKit/Views/ResettableAdjustmentLabel.swift) is wired into every row builder in Light, Develop, Adjust, Color (including white balance and per-channel mixer/grading rows), and Effects (including vignette/grain) inspectors. Confirmed via grep that no row bypasses the shared component.
- **Reset icons removed**: `arrow.uturn.backward` row-level buttons are gone from all five inspector files; only section-level `sectionResetButton` actions remain (e.g. "Reset Mixer", "Reset {channel}"), matching the AC's "section/panel reset actions remain available."
- **Single click / drag / text-field edit unaffected**: `onTapGesture(count: 2)` is the only pointer gesture on the label; sliders/text fields are untouched siblings. No regression risk identified.
- **Undo coalescing**: `endUndoGrouping()` was already present on Light/Color/Effects reset functions and is newly added to Adjust and Develop resets in this commit, closing the gap. `AppViewModel.updateDocument(debounced:)` now cancels any pending `previewDebounceTask` on a non-debounced (reset) call, so an in-flight slider-drag preview can't clobber the reset's immediate preview — addresses "updates the preview before mouse-up."
- **Accessibility**: Each row/slider carries a named `accessibilityAction` ("Reset to neutral" / "Reset to As Shot" / "Reset to decoder default") independent of the double-click gesture. Repeated-label rows (mixer channels, grading zones) pass contextual titles (e.g. "\(channel.title) \(control.title)") so VoiceOver names stay unambiguous.
- **Test coverage**: `Tests/LumoKitTests/ResettableInspectorTests.swift` (new) exercises representative controls across Develop/Light/Adjust/white-balance/Color/Mixer/Grading/Effects/Vignette/Grain, asserting the reset row hits neutral while sibling rows are untouched, plus a dedicated test that a reset ends an active slider undo-group before recording its own entry.

**Build & tests**: `swift build` clean; `swift test` — 510 passed, 26 expected skips, 0 failures. Matches the implementer's reported numbers.

**Note (non-blocking, out of scope)**: The working tree also carries uncommitted changes to ColorInspectorView.swift/ColorGradingAdjustments.swift/AppViewModel+Color.swift and three test files that add a color-grading wheel control — unrelated to this issue's commit. Left untouched; flagging so it isn't mistaken for LUMO-089 scope.

No blockers. Verification passes.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T16:04:24.227Z: Double-click label reset verified across Light/Develop/Adjust/Color/Effects; 510 tests pass, 0 failures. No blockers.
