---
id: LUMO-021
title: Build a virtualized library grid with multi-selection
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:library
  - phase:3
created: 2026-08-30T18:30:24.083Z
updated: 2026-08-31T18:22:01.814Z
depends_on:
  - LUMO-019
  - LUMO-020
estimate: 5
order: a0
board: product
commits:
  - 54917a0
---

## Objective

Provide a fast grid-first browsing surface for hundreds or thousands of assets.

## Context

Part of **Epic 3 — Folder library and rapid culling**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Use lazy/virtualized layout with selection and active-photo distinction.
- Request thumbnails only for visible and near-visible cells.
- Support click, command-click, shift-range, and select-all semantics.
- Show rating/flag state without obscuring the image.

## Acceptance criteria

- [ ] A 1,000-item library does not instantiate or decode every cell eagerly.
- [ ] Selection semantics match native macOS expectations.
- [ ] Scrolling remains responsive while thumbnails arrive.
- [ ] Opening the active item enters Edit without waiting for full RAW decode.

## Verification

- Add selection model tests and profile a synthetic 1,000-item grid.

## Out of scope

- Map, face, or album views.

### Comment — codex @ 2026-08-31T17:10:18.932Z

Implemented in 619f921: added a LazyVGrid library surface with active-vs-multi-selection state, native click/Command-click/Shift-range/select-all semantics, rating/flag overlays, Return/double-click edit handoff, and grid-aware keyboard navigation. Added demand-driven visible-cell thumbnail admission/cancellation while preserving filmstrip/source-browser behavior. Verification: swift test passed (347 tests, 20 skipped), swift build -c release passed, git diff --check passed, dg validate passed with only pre-existing runner/context warnings.

### Comment — claude @ 2026-08-31T18:21:59.395Z

Verification report (counterpoint agent, independent of human review):

Scope reviewed: LibrarySelectionModel/LibraryGridLayout, LibraryGridView, ImageCollection demand-driven thumbnail admission, AppViewModel grid wiring, KeyboardShortcuts grid nav, FilmstripView/SourceBrowserView thumbnail lifecycle, and both new test files, against 619f921.

Finding (blocker, fixed in 54917a0): `ImageCollection.reconcileSelection()` decided whether to fall back to selecting the first item based on the selection's emptiness *before* calling `LibrarySelectionModel.reconcile(with:)`, not after. When the only selected/active item was itself removed (e.g. an unreadable file dropped during metadata scan, or any item pruned by a rescan), `reconcile` legitimately produces an empty selection, but the pre-check had already routed past the fallback branch — leaving a non-empty library with no active item. This silently broke arrow-key navigation and Return-to-edit (both depend on `activeID`) until the user manually clicked a cell, undermining the "selection semantics match native macOS expectations" acceptance criterion. Reproduced via debug trace (activeID: `bad-file` -> nil after reconcile, pre-fix) confirming the exact path exercised by the existing `testUnreadableImageIsReportedWithoutDiscardingReadableFiles` scenario, which just didn't assert on selection state.

Fix: reorder to reconcile first, then fall back to the first available item if the result is empty. Added regression test `testRemovingActiveItemFallsBackToRemainingSelection` (LibraryScanTests.swift), which fails against the pre-fix code and passes after.

Other areas reviewed with no blocking issues: selection click/shift-range/select-all semantics (well covered by LibrarySelectionTests), demand-driven thumbnail admission/cancellation for the virtualized grid (covered by LibraryGridTests, matches the "don't decode every cell" criterion), keyboard routing for grid vs. filmstrip mode, and Swift 6 concurrency (no new Sendable/actor issues introduced).

Verification commands run: `swift build` (clean), `swift test` (348 tests, 20 skipped, 0 failures — includes new regression test), `swift build -c release` (clean), `git diff --check` (clean), `dg validate` (OK, only pre-existing warnings unrelated to this issue).

Verification commit: 54917a0 "fix(LUMO-021): keep an active selection after the active item is removed".

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T18:22:01.812Z: Independent verification found and fixed a selection-fallback bug: removing the active item left no active selection. Fixed in 54917a0 with a regression test; full suite green.
