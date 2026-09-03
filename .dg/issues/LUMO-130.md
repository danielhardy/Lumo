---
id: LUMO-130
title: Restore selected images when returning from Library to Edit
type: bug
status: done
priority: high
labels:
  - navigation
  - library
  - ux
created: 2026-09-02T12:45:19.141Z
updated: 2026-09-02T14:55:05.422Z
order: a0
board: product
commits:
  - cb243ad
---

## Objective

Restore and display the selected images when returning from Library to Edit.

## Context

Reproduction: open or import files, select one or more images in Library, switch to Edit, then
return to the selected edit view. The selection remains visible in the library/navigation state,
but none of those images opens in the canvas. That creates a broken workflow because users cannot
continue editing the assets they just selected. Verify the fix alongside zoom/presentation state,
including the existing black-canvas regression above 100%, so a valid selection is not mistaken for
a rendering failure.

## Acceptance criteria

- [ ] After Library → Edit navigation, the selected active image is loaded and displayed in the
      canvas without requiring a second click or re-import.
- [ ] Multiple selected images remain selected, while the active item is deterministic and matches
      the existing Library selection semantics; selecting another item in Edit still works.
- [ ] Returning to Edit preserves or safely re-establishes the needed source/preview state across
      repeated Library ↔ Edit transitions, including when thumbnail or preview loading is pending.
- [ ] Stale asynchronous loads cannot replace the selected image with a blank or previously viewed
      image, and a genuine load failure is surfaced clearly.
- [ ] Add regression coverage for single-selection, multi-selection, repeated navigation, and
      selection/preview timing.

## Implementation notes

Trace navigation state, active-selection identity, source loading, and preview publication together;
do not clear selection merely to make the transition appear successful. Preserve the existing
per-photo edit/persistence behavior and ensure the Edit canvas is explicitly invalidated or
re-requested when the selected source changes.

### Comment — codex @ 2026-09-02T14:51:22.875Z

Implemented in cb243ad. Library selection now hands off by stable activeID; returning to Edit reuses an already prepared source and re-requests a missing preview without resetting canvas presentation state. Added regressions for single/multi-selection, repeated navigation with >100% zoom, preview timing, and stale source preparation. Verification: swift test (605 passed, 13 skipped), swift build -c release, git diff --check, dg validate OK; validator reports the pre-existing unknown pickup-model warning.

### Comment — claude @ 2026-09-02T14:55:02.376Z

## Independent verification report

**Scope reviewed:** commit cb243ad (Sources/LumoKit/Models/ImageCollection.swift, Sources/LumoKit/ViewModels/AppViewModel.swift, Tests/LumoKitTests/NavigationStateTests.swift).

**Correctness**
- `ImageCollection.selectedItem` now resolves via `selection.activeID` instead of `selectedIndex`, matching the id-based selection model used elsewhere (`syncSelectedIndex`, `reconcileFilteredSelection`). It is a strict improvement: a stale/out-of-bounds index could previously alias to the wrong item after removals, whereas an id lookup fails safe (nil) instead.
- `openActiveCollectionImage` reuse path: gated on `activeAssetID == item.id`, reuses the in-flight `loadTask` (revision-checked in `prepareAndInstall` via `request.sourceRevision == sourceRevision`) rather than enqueueing a duplicate preparation. On preparation failure, `imageSource`/`sourceImage` stay nil and `loadTask` clears, so the next Library→Edit transition correctly falls through to a retry via `openImage` instead of getting stuck.
- Filter-hidden active items: `selectedItem` deliberately does not check `filteredIndices` (same as the prior index-based version and consistent with `reconcileFilteredSelection`'s comment about preserving the active asset across filter changes) — not a regression.
- Zoom/canvas presentation state is preserved across the reuse path since it returns early without touching `canvasState`/`previewCoordinator.cancel()` (only `load()` resets those), matching the acceptance criterion about the black-canvas-above-100% concern.

**Maintainability:** the nested-condition reuse logic in `openActiveCollectionImage` is dense but well commented with the rationale (non-cancellable preparation, avoiding duplicate work); no simplification needed.

**Security / performance:** no external inputs involved; `items.first { $0.id == activeID }` is O(n) over the library but only called from a handful of low-frequency UI entry points — negligible.

**Checks run independently (session 01MTK7S1YL6GZBBN7O):**
- `swift build` — clean.
- `swift test --filter WorkspaceNavigationTests` — 6/6 passed, including the three new regression tests (single/multi-selection handoff by activeID, prepared-source reuse with missing-preview republish, stale-preparation-cannot-clobber-newer-selection).
- `swift test` (full suite) — 605 passed, 13 skipped, 0 failures.
- `git diff --check` on cb243ad — clean.

No blockers found. No code changes made during verification (none needed).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T14:55:05.201Z: Verified: activeID-based selection handoff restores selected image on Library→Edit return; full test suite 605/0 failures.
