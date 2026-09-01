---
id: LUMO-028
title: Ship the Light inspector with reset and interaction semantics
type: task
status: done
priority: high
labels:
  - mvp
  - epic:light
  - phase:4
created: 2026-08-30T18:30:26.475Z
updated: 2026-08-31T20:11:39.813Z
depends_on:
  - LUMO-025
  - LUMO-026
  - LUMO-027
  - LUMO-013
  - LUMO-009
estimate: 5
order: a0
board: product
commits:
  - b7b4742
---

## Objective

Present the complete Light toolset in a collapsible, responsive inspector without leaking CIFilter concepts.

## Context

Part of **Epic 4 — Photographic Light controls**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Use photographer-facing labels/readouts and the specified ranges.
- Support double-click label/value reset, per-control reset, reset Light, and reset photo handoff.
- Group slider gestures for undo and interactive/settled rendering.
- Provide a usable tone-curve editor with keyboard/accessibility support.

## Acceptance criteria

- [ ] All Light controls are reachable without modal UI.
- [ ] Resets affect exactly the intended scope and are undoable.
- [ ] Dragging remains responsive while rendering and produces one undo step.
- [ ] The inspector remains interactive during render cancellation/settling.

## Verification

- Add control model/reset/gesture tests and perform accessibility/keyboard smoke testing.

## Out of scope

- Pixel-local adjustment brushes.

### Comment — codex @ 2026-08-31T20:06:36.937Z

Implemented in commit 9fe768d. Shipped the photographer-facing Light inspector with collapsible Tone and Tone Curve sections, six specified controls/ranges, double-click label/value resets, per-control and panel resets, accessible draggable/adjustable curve points, preview gesture coalescing, bounded per-photo undo/redo history, reset-photo handoff, and Light-aware before/after baseline. Added focused model/view-model/curve/history/photo-handoff tests. Verification: swift test passed (378 tests, 20 expected skips), swift build -c release passed, git diff --check passed, dg validate passed with only pre-existing warnings.

### Comment — claude @ 2026-08-31T20:11:36.137Z

Verification report (counterpoint agent).

Scope: independent correctness/maintainability/security/performance pass over commit 9fe768d (the Light inspector).

Findings — 2 confirmed bugs, both fixed in commit b7b4742 (localized, no product-behavior/API change):
1. Tone-curve accessibility bug: `setToneCurvePoint` appended the synthetic first interior point to the *unsorted* points array, then bounds-checked its index against that array before normalization. The appended point always landed at the last index, so the guard always failed — VoiceOver/keyboard adjustment could never add the curve's first point (dragging worked fine via `addToneCurvePoint`). This directly contradicted the "keyboard/accessibility support" acceptance criterion. Fixed, with a regression test (`testAccessibilityAdjustableActionAddsTheFirstCurvePoint`).
2. Undo/redo keyboard bug: `KeyMonitor`'s Cmd-Z handling only checked Shift on the redo branch. Cmd+Shift+Z with an empty redo stack fell through to the undo branch and silently undid the user's last edit instead of no-op'ing — a real data-loss-shaped bug touching "resets ... are undoable." Fixed by scoping the branches to Shift explicitly. Could not add an automated regression test: `KeyMonitor.handle` reads the global `NSApp`, which is nil in this repo's headless `swift test` process (a pre-existing limitation, not introduced by this fix) — verified correct by manual trace instead.

No other correctness, security, or performance issues found in the diff (EditHistory bounded undo/redo, LightControl/AppViewModel+Light bindings, EditDocument.originalForComparison, MenuCommands/InfoInspectorView wiring all check out against the acceptance criteria and existing tests).

Verification commands (all clean):
- `swift test` — 380 tests, 20 expected skips, 0 failures (378 baseline + 2 new).
- `swift build -c release` — succeeded.
- `git diff --check` — clean.
- `dg validate` — OK, only pre-existing warnings (agents.pickup.runner model name, LUMO-023/066 context completeness).

Verification commit: b7b4742.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T20:11:39.812Z: Verified LUMO-028 Light inspector: found and fixed two bugs (tone-curve keyboard-add-first-point guard, Cmd+Shift+Z falling back to undo). swift test/release build/git diff --check/dg validate all clean.
