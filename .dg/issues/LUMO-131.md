---
id: LUMO-131
title: "Regression: black canvas reappears when zooming past 100%"
type: bug
status: done
priority: high
labels:
  - bug
  - canvas
  - rendering
  - regression
created: 2026-09-02T12:45:45.216Z
updated: 2026-09-02T15:08:00.515Z
order: a0
board: product
commits:
  - 87da92f
---

## Objective

Fix the regression where the editor canvas turns black when zooming past 100%.

## Context

LUMO-094 addressed black frames for explicit zoom, fill, comparison zoom, panning, and pinch
navigation, but the failure has returned in the current build when the zoom exceeds 100%. This
blocks editing because the user loses the visual source precisely when inspecting detail. Treat it
as a regression against LUMO-094 and verify the interaction across the navigation, render-resolution,
preview-publication, and Metal presentation boundaries rather than only checking the zoom control.

## Acceptance criteria

- [ ] Zoom values just above 100% and substantially above 100% keep a valid image visible in the
      main canvas; no indefinite black frame is published.
- [ ] Scroll-wheel, pinch, explicit zoom, and panning behave consistently above 100%, including
      comparison mode, without blanking either panel.
- [ ] While a higher-resolution render is pending, the last valid frame remains visible or a clear
      loading state is shown; failed requests do not leave a permanent black canvas.
- [ ] Switching photos, crop state, comparison mode, or zoom cannot publish a stale/blank frame over
      the active photo.
- [ ] Add regression coverage that exercises the >100% path through preview rendering and surface
      presentation, and record the reproduction/verification setup in the issue comment.

## Implementation notes

Start from the LUMO-094 fix and compare the current render/presentation path for higher zooms,
including any resolution-planner or backing-size boundary that differs above 1.0 scale. Preserve
the last confirmed frame, reject stale/failed candidates, and keep navigation transforms separate
from persisted edit state. Do not permanently lower render resolution or disable zoom to hide the
failure.

Related: LUMO-094.

### Comment — codex @ 2026-09-02T15:04:27.193Z

Implemented in commit 87da92f. Fixed the >100% regression at the Metal presentation boundary by clipping the transformed native-resolution candidate to the drawable before source-over composition and enforcing a drawable-sized final extent; invalid render candidates are rejected so PreviewSurface retains the last confirmed frame. Added preview/surface regressions for 101% and 800% zoom, non-zero crop extents, native-detail planning, and invalid-candidate retention. The opt-in Metal presentation benchmark now exercises 101% and 800% with the same presentation helper.

Verification setup: standard 64x48 gradient fixture through PreviewCutoverTests with zooms 1.01 and 8.0; surface test uses a 640x400 source at offset extent (37,19), 320x240 drawable, and asserts non-background center pixels; hardware check used LUMO_METAL_BENCHMARK=1 LUMO_METAL_BENCHMARK_ITERATIONS=8 on the generated 1280x800 source and a real CAMetalLayer. Focused preview/surface tests passed (19); release build passed; isolated pre-existing CropWorkflowTests re-entry test passed; dg validate passed with only the known pickup-model warning. Full suite: 608 passed, 13 skipped, with the known timing-sensitive LUMO-132 crop re-entry failure.

### Comment — claude @ 2026-09-02T15:07:57.603Z

Counterpoint verification (independent review, agent: claude/sonnet).

Reviewed commit 87da92f against the acceptance criteria and re-ran all checks independently:

- Code review: `PreviewSurface.present` now rejects non-finite/zero-extent images before mutating
  `image`/`space`/`currentDetail`, so a failed render cannot overwrite the last confirmed frame
  (Sources/LumoKit/Views/PreviewSurface.swift:51-58). The new `presentationImage(_:navigation:destination:)`
  clips the transformed candidate to the drawable extent before and after compositing over the
  letterbox, bounding the Core Image working extent at >100% zoom regardless of source resolution
  (PreviewSurface.swift:376-400). `draw(in:)` bails out before `isDrawing` is set when either guard
  fails, so a rejected candidate cannot deadlock future draws, and the existing GPU-failure path
  (`rejectPresentation`) is untouched. No public API/schema changes; change is localized to the
  presentation boundary as scoped.
- Ran the two new/target suites directly: `swift test --filter "PreviewCutoverTests|PreviewSurfaceTests"`
  -> 19/19 passed, including `testZoomJustAboveAndFarAbove100PercentUsesNativePreviewAndKeepsSurfaceFrame`,
  `testPresentationImageRemainsBoundedAbove100PercentAndKeepsTheSourceVisible`, and
  `testInvalidCandidateCannotBlankTheLastConfirmedFrame`.
- `swift build -c release` — clean.
- Full suite `swift test` — 608 passed, 13 skipped, **0 failures** (the LUMO-132 timing-sensitive
  crop re-entry flake noted in the implementer's comment did not reproduce this run).
- `dg validate` — OK, only the known pickup-model warning.
- `git status --porcelain` confirms no unexpected changes to Sources/Tests/Package.swift beyond the
  reviewed commit; pre-existing unrelated working-tree modifications (.dg issue/log files, README,
  .gitignore) predate this session and were left untouched.

No blockers found. No follow-up child tickets warranted — the fix is scoped to the presentation
boundary per the implementation notes, with regression coverage at both the geometry (CIImage extent)
and surface-state (last-valid-frame retention) levels, plus an updated hardware benchmark path.

Verdict: PASS. Moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T15:08:00.513Z: Independent verification passed: reviewed fix, reran targeted (19/19) and full suite (608 passed/0 failed), release build clean, dg validate OK.
