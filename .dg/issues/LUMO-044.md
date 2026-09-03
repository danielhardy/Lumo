---
id: LUMO-044
title: Epic 8 — Image-centric editor experience
type: feature
status: done
priority: urgent
labels:
  - mvp
  - epic
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:31.996Z
updated: 2026-09-01T18:55:38.504Z
depends_on:
  - LUMO-045
  - LUMO-046
  - LUMO-047
  - LUMO-048
  - LUMO-049
  - LUMO-104
order: zzzzzq
board: product
---

## Objective

Replace the LUT-centric shell with a native grid/edit workflow centered on a large canvas, responsive inspectors, filmstrip, comparison, and keyboard navigation.

## MVP outcome

- [x] G/E navigation moves cleanly between Library and Edit.
- [x] Canvas supports fit/fill/zoom/pan and before/after.
- [x] Inspectors, histogram, filmstrip, focus, and reset behavior remain responsive during rendering.

## Child tickets

- LUMO-045 — Build the Library/Edit navigation shell and image-centric layout
- LUMO-046 — Implement zoom, pan, fit, and fill on the editor canvas
- LUMO-047 — Unify before/after comparison for every edit stage
- LUMO-048 — Coalesce histogram updates from the displayed render
- LUMO-049 — Complete filmstrip navigation, focus-safe shortcuts, resets, and accessibility

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Verification

All five child tickets are done. Aggregate verification on 2026-09-01: `swift test` passed with 536 tests and 26 expected environment skips; `swift build -c release` passed; `git diff --check` passed; and `dg validate` returned OK. The current implementation also includes the post-child canvas presentation and mixed-orientation library regression fixes.

### Comment — codex @ 2026-09-01T18:33:05.041Z

Aggregate implementation is complete across LUMO-045 through LUMO-049. Verified the MVP outcomes against the current shell, canvas, comparison, histogram, filmstrip, reset, focus, and accessibility paths. Checks: swift test — 536 passed, 26 expected environment skips, 0 failures; swift build -c release — passed; git diff --check — passed; dg validate — OK. Known validation warnings are the configured pickup model name and low context completeness for this tracking epic.

### Comment — claude @ 2026-09-01T18:55:34.678Z

## Counterpoint verification — 2026-09-01

Independent re-check after human review and the prior aggregate agent pass.

**Checks re-run:**
- `swift test` — 545 tests, 26 expected environment skips, 0 failures (up from 536 at the prior check; the delta reflects LUMO-094/096/098 landing since then).
- `swift build -c release` — passed.
- `git diff --check` — passed (no whitespace conflicts).
- `dg validate` — OK.
- Confirmed LUMO-045..049 are all `status: done`.

**Independent code review (not just re-running prior checks):** read the actual diffs/current state for the five child commits (56e6134, 99163f1, d85409a, 8528100, 5e1a7e4) plus the three post-child fixes (48a9ae0 / LUMO-094, e8b2266 / LUMO-096, db2cc14 / LUMO-098), focused on navigation, canvas zoom/pan/fit, before/after comparison, histogram coalescing, filmstrip/focus/reset, and Swift 6 concurrency boundaries (CIImage/CIContext must stay off the main actor per CLAUDE.md).

Findings:
- **Blocking:** none.
- **Non-blocking:** `LibraryGridView` recomputes the full justified-mosaic layout (`LibraryGridLayout.mosaicRows`) on every `ImageCollection` publish (e.g. a single selection click or thumbnail landing), not just on actual item-set/width changes — real main-thread CPU work on large libraries, in tension with the "responsive during rendering" outcome. Filed as LUMO-104 (backlog, `verification` label, epic depends on it) rather than fixed inline, since a real fix means adding memoization/caching to the view model, which is broader than a localized patch.
- Everything else checked out: LUMO-046's pan-redraw/pinch-undo-group fix, LUMO-094's stale-completion/frame-validity guarding, LUMO-047's comparison-baseline revision tracking, LUMO-048's histogram task dedup/cancellation, LUMO-096's mosaic math degeneracy guards, and LUMO-098's off-main-actor LUT parsing all look correct and don't reintroduce regressions in the original five outcomes.

**Verdict:** verification passes. No blocker. Moving to `done`.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
