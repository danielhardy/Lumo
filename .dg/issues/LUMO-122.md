---
id: LUMO-122
title: Guard against cross-purpose state pollution in the shared ResolutionPlanner
type: task
status: done
priority: low
labels:
  - verification
  - performance
  - rendering
created: 2026-09-02T02:48:45.878Z
updated: 2026-09-02T12:46:43.160Z
parent: LUMO-108
depends_on:
  - LUMO-108
order: a0
board: product
commits:
  - 955cc36
---

## Objective

Prevent one caller's viewport/crop from corrupting another caller's discrete detail level in
`AppViewModel`'s single shared `ResolutionPlanner` instance.

## Context

Found during independent verification of LUMO-108 (commit `79b96cb`). `AppViewModel` holds one
`ResolutionPlanner` (`AppViewModel.swift:1290`) and calls `previewRenderTargetSize(for:)` — which
mutates the planner's hysteresis state via `plan(...)` — from four call sites: the main preview's
settled request, its interactive request, the side-by-side comparison baseline
(`scheduleOriginalPreview`, using `document.comparisonBaseline`), and the histogram fallback
request.

This is safe today only because every call site happens to pass the same crop rect (comparison
baseline preserves `crop` — see `EditDocument.originalForComparison`) and the same
`previewBackingSize` (side-by-side panels are always equal-width halves of the same window, so
both `MTKView` drawables report the same backing size). `ResolutionPlanner.level(for:current:)`
mixes those calls into one hysteresis state (`ResolutionPlanner.swift:97-108`), so if a future
change ever gives two callers genuinely different viewports or crops (e.g. independently
resizable comparison panels, or a comparison baseline rendered at a different zoom), the shared
`selectedLevel` would thrash or silently apply one caller's detail level to another's request, with
no compiler or test signal.

## Acceptance criteria

- [ ] Either give each logical surface (main preview, comparison baseline, histogram) its own
      `ResolutionPlanner` instance, or make `ResolutionPlanner` explicitly keyed per (purpose)
      so unrelated call sites cannot share hysteresis state.
- [ ] Add a regression test that fails if two call sites with different viewport sizes or crops
      are planned through the same `AppViewModel` instance and observe each other's level.
- [ ] No behavior change for the current single-viewport, shared-crop case other than making the
      isolation explicit.

## Implementation notes

Low priority / non-blocking: not a defect in current behavior, since all present call sites agree
on crop and viewport. This is a latent coupling risk for the next feature that touches
`previewRenderTargetSize`, `scheduleOriginalPreview`, or independently-sized comparison panels.
See `docs/LUMO-108-RESOLUTION-PLANNING.md` for the planner's design rationale.

### Comment — codex @ 2026-09-02T04:55:52.723Z

Implemented in commit 955cc36. ResolutionPlanner hysteresis is now isolated across main preview, comparison baseline, and histogram surfaces; main settled/interactive requests intentionally share state. All planners reset on source changes. Added an AppViewModel regression test covering cross-surface crop/detail pollution. Verification: swift test --filter ResolutionPlannerTests and full swift test passed (595 tests, 13 expected skips).

### Comment — claude @ 2026-09-02T12:46:38.877Z

Counterpoint verification: PASS.

Reviewed commit 955cc36 against acceptance criteria:
- Each logical surface (mainPreview, comparisonBaseline, histogram) now gets its own ResolutionPlanner instance (AppViewModel.swift:1423-1425), keyed via ResolutionPlannerSurface enum. Main preview settled/interactive requests intentionally continue to share one planner, as documented and intended.
- resetResolutionPlanners() replaces the single reset() call at the source-change site (AppViewModel.swift:709); no dangling references to the old shared `resolutionPlanner` property remain (grep clean).
- Regression test testAppViewModelDoesNotShareHysteresisBetweenRenderingSurfaces (ResolutionPlannerTests.swift) drives a high-detail crop through .mainPreview then asserts .comparisonBaseline and .histogram independently settle at .5 scale rather than inheriting the main surface's native-resolution hysteresis — this fails without the fix (a shared planner would keep the comparison/histogram calls at a higher detail level due to downgrade hysteresis).
- Behavior for the current shared-crop, single-viewport case is unchanged: all call sites still compute the same required scale at any given moment (comparison baseline preserves crop; histogram uses the same document), so the split into independent planners does not change today's selected levels, only removes the latent cross-surface coupling.

Checks run:
- `swift test --filter ResolutionPlannerTests` — 4/4 passed.
- `swift test` (full suite) — 595 tests, 13 expected skips, 0 failures. Matches the implementer's reported result.
- `git status --porcelain` on Sources/Tests — clean (two unrelated pre-existing untracked docs files only).

No blockers, no localized fixes needed, no child tickets warranted. Moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T12:46:41.204Z: Cross-surface hysteresis isolation verified independently: separate ResolutionPlanner per surface, regression test confirms no pollution, full swift test suite green (595 tests, 13 skipped, 0 failures).
