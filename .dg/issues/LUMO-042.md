---
id: LUMO-042
title: Reframe the LUT library as a Look inspector
type: task
status: done
priority: medium
labels:
  - mvp
  - epic:lut
  - phase:7
created: 2026-08-30T18:30:31.224Z
updated: 2026-09-01T13:50:14.059Z
depends_on:
  - LUMO-041
  - LUMO-009
estimate: 5
order: zzzy
board: product
---

## Objective

Retain nested folders, search, intensity, and keyboard browsing in an optional Look section integrated with the editor.

## Context

Part of **Epic 7 — LUTs as an optional Look stage**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Add an explicit None row and clear selected state.
- Retain recursive folders, search, counts, and up/down auditioning where focus rules permit.
- Make selection/intensity per-photo and undoable.
- Keep derived LUT creation accessible without dominating the edit workflow.

## Acceptance criteria

- [ ] A user can edit fully without configuring a LUT folder.
- [ ] Selecting None clears the visual effect and persists.
- [ ] Search/folder grouping and keyboard auditioning remain functional.
- [ ] Look controls participate in resets without affecting unrelated panels.

## Verification

- Add state/reset/navigation tests and regression-smoke the derive workflow.

## Out of scope

- Online LUT marketplace.

### Comment — codex @ 2026-09-01T13:47:44.207Z

Implemented in commit e5fddb5. Reframed the LUT library as an optional Look inspector tab with an explicit None row, ID-based selection that distinguishes missing references, per-photo intensity, scoped undoable Look reset, retained nested folders/search/collapse and keyboard look auditioning, and in-panel folder/derive entry points. Verification: swift test (470 passed, 25 expected skips), swift build -c release, git diff --check, and dg validate passed; validate reports only pre-existing runner-model/context warnings.

### Comment — claude @ 2026-09-01T13:50:11.534Z

## Verification report (counterpoint, claude/sonnet)

**Reviewed:** commit e5fddb5 (LUT library → Look inspector reframe), diffed against LUTSidebar.swift, AppViewModel.swift, ContentView.swift, InfoInspectorView.swift, KeyboardShortcuts.swift, MenuCommands.swift, StatusBar.swift, and the two test files.

**Checks run:**
- `swift build` — clean.
- `swift test` — 470 passed, 25 expected skips, 0 failures.
- `swift build -c release` — clean (pre-existing CIKernel deprecation warnings only, unrelated).
- `git diff --check` — clean.
- `dg validate` — OK (same pre-existing runner-model/context warnings noted in the implementation comment).

**Correctness:** ID-based selection (`LUTID`) correctly distinguishes explicit None (`lutID == nil`) from an unresolved/missing reference (`resolvedLUT(id) == nil` while the ID is retained) — verified via `selectedLookID`/`isLookNoneSelected`/`resolvedLUT`. `resetLook()` scopes to `document.lut` only, confirmed by `testLookResetIsScopedAndUndoable` (adjustments untouched, one undo step). Per-photo persistence of selection/intensity confirmed by `testLookSelectionAndIntensityStayWithTheirPhoto`. Keyboard auditioning (`selectPreviousLUT`/`selectNextLUT`) and folder/search/collapse state carried over intact from the prior sidebar implementation. No dangling references to the removed `LUTSidebar` type or the old toolbar intensity/folder controls.

**Fix applied (localized, no behavior change):** `resetLUT()` was left in `AppViewModel.swift` as a naming-compatibility shim for `resetLook()`, but nothing in the codebase calls it — dead code. Removed it in 5e5ece0. Rebuilt and re-ran the full test suite after the change: still 470 passed / 25 skipped / 0 failures.

**No blockers, no broader findings warranting a child ticket.** Acceptance criteria (edit without a LUT folder, None clears and persists, search/folder/keyboard auditioning intact, Look resets scoped) are all covered by existing/added tests and manual code reading.

Verdict: **pass**.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
