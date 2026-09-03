---
id: LUMO-048
title: Coalesce histogram updates from the displayed render
type: task
status: done
priority: high
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:33.358Z
updated: 2026-09-01T17:22:11.059Z
depends_on:
  - LUMO-045
  - LUMO-013
estimate: 3
order: a0
board: product
commits:
  - "8528100"
---

## Objective

Adapt the inherited histogram so it reflects the current displayed edit without competing with slider responsiveness.

## Context

Part of **Epic 8 — Image-centric editor experience**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Compute from the same displayed revision and color pipeline.
- Cancel/coalesce transient histogram work.
- Gate work when the histogram is hidden.
- Prevent results from an older photo/edit publishing late.

## Acceptance criteria

- [x] Histogram changes after settled edits and matches before/after state.
- [x] Hidden histogram causes no computation.
- [x] Rapid slider input does not queue histogram work per tick.
- [x] Late results cannot replace the current revision.

## Verification

- Extend fake-engine histogram gating, coalescing, revision, and comparison tests.

## Out of scope

- Clipping overlays unless separately prioritized.

### Comment — codex @ 2026-09-01T17:19:07.548Z

Implemented in commit 8528100. Histogram requests now use the exact settled displayed RenderRequest (including comparison state and working space), cancel when hidden or superseded, deduplicate duplicate open-vs-publication scheduling, and reject late results by source/display revision. Extended FakeRenderEngine and DevelopInspectorTests for gating, rapid-edit coalescing, late revisions, and comparison. Verification: swift test — 527 passed, 26 expected skips; swift build -c release — passed; git diff --check — passed.

### Comment — claude @ 2026-09-01T17:22:01.352Z

Independent verification: PASS.

Reviewed commit 8528100 (AppViewModel.swift histogram gating/coalescing, FakeRenderEngine, DevelopInspectorTests) against all four acceptance criteria:
- Gating: isInspectorPresented/inspectorTab didSet cancel+clear histogram when hidden or off the Info tab; updateHistogram() re-guards the same condition before scheduling.
- Coalescing: every display-affecting mutation (document edits, LUT intensity, zoom, comparison toggle, history restore, preview submission) increments displayRevision and cancels the in-flight task; only the settled PreviewCoordinator publication schedules a new histogram tally, so rapid slider ticks never queue work.
- Same displayed request: updateHistogram(for:) uses the exact settled RenderRequest (document, lut, renderScale, space) from the publication rather than re-deriving state, so it matches the on-screen comparison request (before/after, look/no-look).
- Late-result rejection: histogram completion re-checks Task.isCancelled, isInspectorPresented/tab, sourceRevision, displayRevision, and imageSource before publishing; confirmed via testLateHistogramResultCannotReplaceANewerEdit.
- Open/publication race: histogramTaskRevision + histogramTaskRequest dedup avoids double-scheduling when opening the inspector races the settled publication already in flight.

PreviewCoordinator's own latest-wins revision counter guarantees publishPreview only ever sees the current settled request, so updateHistogram(for:) can trust publication.request without an extra staleness check — verified by reading PreviewCoordinator.submit/nextRevision.

Reran the full verification: `swift build` clean, `swift test` — 527 passed, 26 expected skips (matches the implementer's report), `swift build -c release` clean, `git diff --check` clean. No Swift 6 concurrency opt-outs introduced (grep for @unchecked Sendable / nonisolated(unsafe) / @preconcurrency in AppViewModel.swift: none).

No blocking issues found. Minor non-blocking style note (not filed as a ticket, too small to warrant one): the `displayRevision &+= 1; cancelHistogram(clear: false)` pair is repeated at 7 call sites and could be a single private helper — cosmetic only, no behavioral risk.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T17:22:11.057Z: Independent verification passed: all 4 acceptance criteria confirmed against commit 8528100 (gating, coalescing, displayed-request matching, late-result rejection). swift test 527 passed/26 skipped, release build clean, git diff --check clean, no Swift 6 opt-outs.
