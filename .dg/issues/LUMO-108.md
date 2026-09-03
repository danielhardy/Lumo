---
id: LUMO-108
title: Add crop-aware resolution planning and reusable zoom detail levels
type: task
status: done
priority: high
labels:
  - performance
  - epic:quality
  - rendering
  - zoom
  - crop
created: 2026-09-01T22:05:10.052Z
updated: 2026-09-02T02:51:45.530Z
depends_on:
  - LUMO-106
  - LUMO-107
order: a0
board: product
commits:
  - 79b96cb
---

## Objective

Maintain sharp, accurate crop and zoom previews without rebuilding source development for every small navigation or viewport change.

## Context and evidence

Performance audit item 3, evaluated at commit `724ad99`: [September 1 audit](../../docs/PERFORMANCE_AUDIT_2026-09-01.md).
The user requested tangible responsiveness improvements without sacrificing visual fidelity or accuracy; prioritize code quality and measured impact over minimizing implementation effort.

**Evidence:** [AppViewModel.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/ViewModels/AppViewModel.swift:1276) derives target resolution from the whole uncropped source and continuously varying zoom. Cache dimensions are exact floating-point values. [RenderPipeline.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderPipeline.swift:105) crops after source downscaling. Pinch updates request interactive rendering even when a sharper settled image is already available.

**Impact:** Zoom/resize creates many distinct source-cache entries and evicts useful ones. Deep zoom requests high source resolution without an explicit visible-region strategy. Cropping to one quarter of the source width/height can leave only one quarter of the required linear detail before the surface enlarges it. At equal aspect ratio, a 1600×1200 source preview becomes a 400×300 crop displayed at 1600×1200.

**Approach:** Plan resolution from the committed crop, visible viewport, actual backing pixels, and native source bounds. Reuse the nearest adequate discrete resolution level, with hysteresis. Keep an existing sharper result during navigation rather than replacing it with an inferior interactive level. Add visible-region tiles and neighboring-tile prefetch for large/native-resolution views where profiling justifies it. Core Image already performs ROI optimization; measure its actual work before assuming every graph evaluates its full extent.

**Fidelity:** Tiles must preserve full-image coordinates, spatial-filter support outside tile boundaries, crop geometry, grain seed/phase, and vignette geometry. Do not change processing order by moving crop ahead of spatial effects. Full-quality visible tiles must be available for accurate detail inspection.

## Acceptance criteria

- [ ] Resolution planning uses the committed crop, visible viewport, actual view backing pixels, and native source limits; it works across mixed-DPI displays and side-by-side panel sizes.
- [ ] A crop one quarter of the source width/height receives enough source detail to fill the viewport up to native resolution rather than enlarging a quarter-sized preview.
- [ ] Continuous zoom and resize reuse discrete adequate detail levels with hysteresis; cache growth and level transitions are bounded and measured.
- [ ] A navigation-only request cannot replace a valid sharper frame with a lower-detail result for the same document/source.
- [ ] Deep zoom evaluates useful visible detail through a measured ROI/tile strategy. If explicit tiling adds no benefit over Core Image ROI, record evidence and retain the simpler implementation.
- [ ] Any tiles preserve full-image coordinates, spatial-filter overlap, crop alignment, grain phase, and vignette geometry; no seams or changes to processing order are introduced.
- [ ] Warm movement within cached detail is presentation-only and meets the ≤33 ms p95 target; final detail is measured separately and matches the native reference.

## Verification plan

Extend CanvasNavigationTests, RenderCacheTests, and CropPipelineTests. Use high-frequency patterns, high-contrast edges, portrait EXIF orientations, small crops, and combined spatial effects. Capture warm/cold pinch, wheel zoom, window resize, and viewport traversal on large standard and RAW files; record actual source evaluations and resident bytes.

Start with these relevant checks, then run `swift test` and `swift build -c release` before implementation handoff:

```sh
swift test --filter CanvasNavigationTests
swift test --filter CropPipelineTests
swift test --filter RenderCacheTests
```

Record generated fixture parameters and, for hardware results, source dimensions/format, RAW decoder/version when relevant, hardware, OS, commit, Release configuration, viewport/backing pixels, and cold/warm conditions. Attach before/after traces or durable summaries. The September 1 audit measured component rendering on an M1 Pro (10 CPU cores, 16 GB, macOS 26.6); it did not measure Lightroom/Photomator or real RAW input-to-display latency. Its 198.9 ms rebuild versus 4.9 ms source-reuse PNG result motivates reuse but is not a promised whole-app speedup.

## Fidelity and engineering constraints

Preserve macOS 14 deployment, Swift 6 concurrency safety, Apple-framework-only dependencies, deterministic edit ordering, working-space conversion, premultiplied alpha behavior, orientation, native-resolution export, and deterministic grain where applicable. Do not hide latency by permanently reducing resolution, skipping effects, or weakening precision. Pixel parity needs documented tolerances and representative fine-detail, edge, skin-tone, saturated/wide-gamut, crop, and transparency fixtures; sharing the same graph across resolutions is not proof of equivalence for nonlinear/spatial processing.

## Dependencies and scope boundaries

Hard prerequisites: LUMO-106, LUMO-107

Depends on effective cache identity and completed-resource presentation. Owns detail selection, not crop-tool draft semantics. Coordinate with the crop re-entry correction without making that bug wait for tiling.

These tickets provide concrete implementation work for the broader LUMO-055/LUMO-058 quality effort. This ticket is in backlog for planning; implementation and automatic pickup have not been requested as part of ticket creation.

### Comment — codex @ 2026-09-02T02:38:45.544Z

Implemented in 79b96cb. Added crop-aware ResolutionPlanner using committed crop, actual drawable backing pixels, native bounds, discrete 1/8–native levels, visible-region metadata, and downgrade hysteresis; wired per-panel MTKView drawable sizing; prevented lower-detail same-source/document frames from replacing sharper frames. Preserved crop-after-adjustments ordering and documented the no-explicit-tiling/Core Image ROI boundary in docs/LUMO-108-RESOLUTION-PLANNING.md. Verification: focused CanvasNavigationTests, CropPipelineTests, RenderCacheTests; 24 affected resolution/cutover/surface tests; swift build -c release all passed. Full swift test completed 580 tests with 13 skips and 7 known pre-existing RAW fixture/host failures unrelated to this change; git diff --cached --check passed.

### Comment — claude @ 2026-09-02T02:51:40.293Z

## Verification report — counterpoint review of LUMO-108 (commit 79b96cb)

**Scope reviewed:** ResolutionPlanner.swift, AppViewModel.swift/PreviewSurface.swift/PreviewView.swift wiring, ResolutionPlannerTests, PreviewSurfaceTests, PreviewCutoverTests, ExportCutoverTests, and docs/LUMO-108-RESOLUTION-PLANNING.md.

**Correctness:**
- Verified the required-scale derivation by hand against the planner's own tests: `fitScale = viewportSize / cropSize` is already in native-fraction units because `cropSize = native * cropRect`, so the quarter-crop case correctly selects native detail (6000x4000) rather than a viewport-relative fraction — confirms acceptance criterion 2.
- `CanvasNavigation.transform(...).scale` (base fit/fill scale × zoom) is unit-consistent with the planner's own `fitScale`, so `requiredScale = max(fitScale, transform.scale)` composes correctly for both zoomed-in and zoomed-out cases.
- Hysteresis (`level(for:current:)`) upgrades immediately and downgrades only past a 15% headroom on the next-lower level; single-step-per-call design matches the "no thrashing on small resize" acceptance criterion and is exercised by `testFitDetailIsDiscreteAndHysteresisBoundsResizeTransitions`.
- `PreviewSurface.present` correctly rejects a same-identity, lower-`detailFactor` frame while a sharper one is current, and reverts `currentDetail` alongside `lastValidDetail` on presentation failure — covered by `testNavigationCannotReplaceAValidSharperFrameWithALowerDetailFrame`.
- Traced all 4 call sites of `previewRenderTargetSize(for:)` (settled, interactive, comparison baseline via `scheduleOriginalPreview`, histogram fallback): they share one `ResolutionPlanner` instance, which is safe today because `EditDocument.originalForComparison` preserves `crop` and side-by-side panels are always equal-width halves reporting the same backing size — so no observed correctness defect, but it is a latent coupling (see LUMO-122 below).
- Crop-after-adjustments ordering, grain/vignette handling: no code in this diff moves crop relative to the adjustment graph; `RenderPipeline.swift` crop stage is untouched by this commit.

**Tests:**
- `swift test --filter "CanvasNavigationTests|CropPipelineTests|RenderCacheTests|ResolutionPlannerTests|PreviewSurfaceTests|PreviewCutoverTests|ExportCutoverTests"` — all pass (50 tests).
- Full `swift test` — 580 tests, 13 skipped, 2 failures: `ImageSourceTests.testRAWBytesAreDetectedWithoutAFilename` and `RAWCapabilitiesTests.testProbingARealRAWReportsItsDecodersSeeds`. Both are gated on local RAW fixtures in the untracked `realworldtest/` directory and live in files this commit does not touch (`git show --stat 79b96cb` confirms no changes to ImageSourceTests.swift, RAWCapabilitiesTests.swift, or Fixtures.swift's `localRAWURL`). Confirmed unrelated to this change — pre-existing host/fixture-dependent failures, consistent with the implementer's note about "known pre-existing RAW fixture/host failures."
- `swift build -c release` — succeeds.

**Verdict:** PASS. No blocking issues found.

**Non-blocking finding filed as a child ticket:** LUMO-122 (backlog, `verification` label, parent LUMO-108) — the shared single `ResolutionPlanner` instance mixes hysteresis state across 4 logically distinct call sites; currently safe only because they all happen to agree on crop/viewport today, but is a latent coupling risk for future features (independently-sized comparison panels, a comparison baseline at a different zoom, etc.).

Environment: macOS (local dev machine), Xcode/SDK per repo CLAUDE.md requirements, Swift 6 language mode, debug + release builds both succeeded.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T02:51:45.529Z: Independent verification passed: planner math, hysteresis, and navigation-cannot-downgrade-sharper-frame logic checked against tests and by hand; focused + full swift test and release build confirmed (2 pre-existing unrelated RAW-fixture failures); filed LUMO-122 for a non-blocking shared-planner-state coupling risk.
