---
id: LUMO-009
title: Implement per-photo undo and redo with gesture grouping
type: task
status: done
priority: high
labels:
  - mvp
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:20.143Z
updated: 2026-08-31T03:47:04.260Z
depends_on:
  - LUMO-007
estimate: 5
order: zh
board: product
commits:
  - c77ef55
---

## Objective

Add bounded per-photo history so a complete slider drag is one undo operation and resets are reversible.

## Context

Part of **Epic 1 — Durable per-photo edit domain**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Snapshot value-state documents, not images or Core Image objects.
- Open one undo group at gesture start and close it at gesture end.
- Cover individual reset, panel reset, reset photo, LUT, and RAW develop changes.
- Clear redo on divergent edits and bound history memory.

## Acceptance criteria

- [ ] A drag through many values undoes directly to its starting value.
- [ ] Undo/redo stays isolated per photo across navigation.
- [ ] Reset operations can be undone in one step.
- [ ] History has a documented bound and never stores rendered images.

## Verification

- Add undo grouping, redo invalidation, navigation isolation, and memory-bound model tests.

## Out of scope

- Named history steps UI.
- Cross-device history.

### Comment — codex @ 2026-08-31T03:45:36.386Z

Implemented in commit c77ef55 (with completed LUMO-007 dependency 39403b9). Added bounded per-photo EditHistory storing only EditDocument snapshots, gesture grouping for adjustment/develop/LUT sliders, redo invalidation on divergent edits, reversible individual/panel/photo resets and LUT/RAW changes, per-photo undo/redo restoration across navigation, and Cmd-Z/Cmd-Shift-Z menu commands. Added focused history and navigation tests. Verification: swift build passed; swift test passed (319 executed, 20 expected skips, 0 failures); swift build -c release passed; dg validate passed with pre-existing warnings for the runner model and LUMO-005 context completeness.

### Comment — claude @ 2026-08-31T03:47:01.142Z

## Verification report — independent counterpoint pass

**Scope reviewed:** commits c77ef55 (per-photo undo/redo) and 39403b9 (per-photo edit-state isolation, its dependency).

**Checks run independently:**
- `swift build` — clean, no diagnostics.
- `swift test` — 319 executed, 20 expected skips (no local RAW fixture), 0 failures. Matches the implementer's reported numbers.
- `dg validate` — OK, same two pre-existing warnings (pickup runner model name, LUMO-005 context completeness) unrelated to this issue.

**Code review findings:**
- `EditHistory` (Sources/LumoKit/Models/EditHistory.swift) stores only `EditDocument` value snapshots — no `CIImage`/`CIFilter`/rendered output — and caps each direction at `maximumDepth = 100`, documented in a doc comment, satisfying "History has a documented bound and never stores rendered images."
- Gesture grouping (`beginGrouping`/`endGrouping`) records one undo entry per completed drag; `recordChange` invalidates redo on every change but only appends an undo entry when no group is open, so a drag through many values undoes directly to its starting value (covered by `testGestureIsOneUndoOperationAndRedoRestoresFinalValue` and `testSliderValuesCommitAsOneUndoOperation`).
- Redo is cleared on divergent edits after an undo (`testDivergentEditClearsRedo`), and history depth is bounded on both stacks (`testEachDirectionIsBounded`).
- Individual/panel/photo resets and LUT/RAW-develop changes all route through `endUndoGrouping()` + `updateDocument`, making each reset one reversible step (`testResetsAndLUTChangesAreReversible`, `testIndividualAndPanelResetsAreEachOneUndoOperation`).
- Per-photo isolation across navigation: `AppViewModel` keys `editSessions` by `PhotoAssetID` and swaps both `document` and `activeHistory` on load (`AppViewModel.swift:382-392`), verified end-to-end by `testUndoHistoryIsIsolatedPerPhotoAcrossNavigation`.
- `applyHistoryDocument` correctly cancels in-flight develop/intensity tasks and re-triggers the original-preview baseline only when `rawDevelop` actually changed — consistent with the existing debounce/baseline contract in `updateDocument(debounced:)`.

**Non-blocking observation (not filed as a ticket — too minor):** `MenuCommands.swift`'s Undo/Redo/Reset Photo menu items don't gate on `viewModel.canUndo`/`canRedo`, so the items are always enabled; calling `undo()`/`redo()` when the stack is empty is already a safe no-op, so this is cosmetic only.

**Verdict: PASS.** All acceptance criteria are met and independently confirmed. No blockers, no new backlog tickets warranted.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T03:47:04.042Z: Independent verification passed: build/tests/dg validate all green, undo/redo grouping, redo invalidation, reset reversibility, and per-photo isolation confirmed by code review and test read-through.
