---
id: LUMO-098
title: Restore broad external .cube LUT and Look file support
type: task
status: done
priority: high
labels:
  - mvp
  - epic:lut
  - phase:7
created: 2026-09-01T17:47:14.153Z
updated: 2026-09-01T19:03:48.070Z
depends_on:
  - LUMO-041
  - LUMO-085
order: y
board: product
commits:
  - db2cc14
---

## Objective

Restore the reliable LUTzy-era workflow for using external `.cube` files and make the Look stage
accept the broadest practical set of standard LUT files.

## Context

Lumo still has a `.cube` model and a canonical Look inspector, but users report that the former
ability to use cube files has been lost. A Look should be usable from an imported or discovered LUT,
not only from a derived result or a narrowly configured location.

## Acceptance criteria

- [ ] A user can add/open or otherwise import an external `.cube` file from a normal file location,
  and it appears in the canonical Look browser without requiring a derived-Look workflow.
- [ ] Common standard `.cube` variants are parsed correctly, including comments/metadata, supported
  3D sizes, and `DOMAIN_MIN`/`DOMAIN_MAX`; unsupported files fail clearly and safely.
- [ ] Selecting an imported cube applies it to the preview and export with adjustable intensity;
  None, missing-file handling, undo, persistence, and copy/paste continue to work.
- [ ] LUT resolution, cache invalidation, and file replacement do not leave a stale cube applied.
- [ ] Add parser, import/discovery, workflow, and preview/export regression coverage, documenting the
  supported format boundary.

## Implementation notes

Relevant code: `CubeLUT.swift`, `LUTLibrary.swift`, `LookInspectorView.swift`, AppViewModel LUT/Look
resolution, and existing LUT tests. Preserve stable `LUTID`/`LUTSettings` persistence and the
single Look surface from LUMO-085; do not trade away current GPU-backed rendering.

### Comment — codex @ 2026-09-01T18:48:45.043Z

Implemented and committed as db2cc14. Restored external Look workflow: import .cube and text-based .look files from ordinary file locations through the Look inspector and File menu; persist security-scoped file references; re-read imported files with a visible Refresh action; and invalidate the GPU LUT cache on library changes/replacements. Hardened parsing for BOMs, tabs, CRLF, comments/metadata, DOMAIN_MIN/MAX, LUT_3D_INPUT_RANGE, finite values, common 3D sizes 2…65, and explicit rejection of 1D/oversized/malformed data. Added parser, discovery/import, replacement, persistence, preview request, and menu regression coverage plus docs/LUT_FORMAT.md. Verification: focused LUT suites passed; full swift test passed (545 executed, 26 expected skips, 0 failures); swift build -c release passed; dg validate passed with only the pre-existing runner-model warning.

### Comment — claude @ 2026-09-01T19:03:43.547Z

## Counterpoint verification report (independent, post-human-review)

**Scope reviewed:** commit db2cc14 (feat(LUMO-098): restore external LUT import support) — CubeLUT.swift, LUTLibrary.swift, AppViewModel.swift, LookInspectorView.swift, MenuCommands.swift, plus added tests and docs/LUT_FORMAT.md.

**Checks run independently:**
- `swift build` — clean, 0 diagnostics.
- `swift test --filter CubeLUTTests|LUTWorkflowTests|LibraryScanTests|MenuCommandTests` — all pass (21+6+22+2 = 51 tests).
- `swift test` (full suite) — 549 executed, 26 skipped, 0 failures. (Count differs slightly from the implementer's reported 545 because LUMO-099 landed additional tests since; no LUMO-098-related failures.)
- `swift build -c release` — clean, 0 diagnostics.
- `dg validate` — OK, only the pre-existing `agents.pickup.runner` model warning (unrelated to this issue).

**Correctness:**
- Parser correctly rejects 1D cubes, oversized/undersized 3D dimensions, reversed DOMAIN_MIN/MAX, non-finite values, and malformed rows before any table allocation — verified via `LUTError` cases and matching tests (`testRejectsUnsupportedOneDimensionalCubeClearly`, `testRejectsOversizedCubeBeforeAllocatingTable`, `testRejectsReversedDomain`).
- BOM/CRLF/tabs/comment handling and `LUT_3D_INPUT_RANGE` compatibility spelling verified against a synthetic vendor-style fixture; table values compute correctly relative to declared domain.
- Import path (`LUTLibrary.importLUT`) and rescan path (`LUTLibrary.scan`) both funnel through `publishCategories()` and fire `onScanned`, which is the single wiring point (`AppViewModel.wireCoordinators`) that calls `engine.invalidateLUTCache()` — confirmed no path exists that updates `categories`/`allLUTs` without also invalidating the GPU cache, so a replaced file cannot leave a stale cube applied.
- Stable `LUTID` (file path derived) is preserved across import/replace/rescan — confirmed by `testRefreshingAnImportedFileReplacesItsTableAtTheSameStablePath` and `testRescanReplacesAFileBackedTableAtTheSameStablePath`.
- Persistence of imported files uses security-scoped bookmarks (`importedBookmarksKey`), restored and re-resolved on `LUTLibrary.init()`; `deinit` releases all scopes. `URL`/`[URL]` are `Sendable`, so the `nonisolated deinit` touching them is safe under Swift 6 mode (consistent with the project's zero-escape-hatch concurrency rule) — confirmed no `@unchecked Sendable` or similar introduced.

**Maintainability/docs:** `docs/LUT_FORMAT.md` accurately documents the supported format boundary (sizes 2…65, DOMAIN_MIN/MAX, LUT_3D_INPUT_RANGE, rejected 1D/oversized/malformed) and matches the implemented behavior.

**No blockers found.** No localized fixes were needed. No new child tickets required — this closes cleanly.

Verdict: **PASS**. Moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T19:03:48.068Z: Independent counterpoint verification passed: build/test/release/dg-validate all green, cache invalidation and stable-LUTID paths confirmed correct, no blockers.
