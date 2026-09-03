---
id: LUMO-126
title: Prevent Dehaze from corrupting image geometry at extreme values
type: bug
status: done
priority: high
labels:
  - effects
  - rendering
  - correctness
created: 2026-09-02T12:45:17.653Z
updated: 2026-09-02T13:14:11.543Z
order: a0
board: product
commits:
  - becaf86
---

## Objective

Make Dehaze safe across its full supported slider range without corrupting image geometry or
orientation.

## Context

The Dehaze control does not appear to behave as a bounded photographic adjustment. A report from
the current editor says that pushing the slider far right can flip the image upside down instead
of increasing the intended effect. This is a correctness failure: a tonal/detail adjustment must
not alter orientation, extent, or spatial arrangement. Re-test at zoom levels above 100% as well,
because the black-canvas regression can obscure whether the rendered result is valid.

## Acceptance criteria

- [ ] Dehaze values across the full UI range produce a valid image with unchanged orientation,
      extent, and pixel geometry; no upside-down or mirrored output occurs.
- [ ] Positive, negative, zero, and maximum-value cases are covered, including representative
      larger images and preview-to-settled transitions.
- [ ] Preview, comparison, and full-resolution export use the same bounded Dehaze behavior and do
      not produce NaN/Inf-driven or otherwise invalid output.
- [ ] Add regression tests that would fail if an extreme Dehaze value changes image orientation or
      collapses the rendered extent.

## Implementation notes

Trace the Dehaze implementation from the Effects model/control through the Core Image/Metal
pipeline and inspect parameter normalization, kernel coordinates, and extent handling. Clamp or
sanitize inputs at the appropriate model/pipeline boundary, preserve color/working-space behavior,
and avoid fixing the symptom by silently reducing the requested adjustment.

### Comment — codex @ 2026-09-02T13:11:17.893Z

Implemented in commit becaf86. Replaced the coordinate-unsafe custom effects blend with Core Image's coordinate-aware alpha blend, preserving the full Dehaze amount and exact input extent; added renderer-side finite/range sanitization, bounded Dehaze tone output, and cache version 17. Added regressions for -100/-1/0/+1/+100 on a 640x400 offset ramp, finite pixels, orientation/extent preservation, and interactive/preview/export parity. Verification: swift test (600 passed, 13 expected skips), swift build -c release, git diff --check, dg validate OK with the pre-existing pickup-model warning.

### Comment — claude @ 2026-09-02T13:14:09.009Z

Verification report (counterpoint agent, independent of human review).

Scope reviewed: commit becaf86 (Sources/LumoKit/Models/RenderPipeline.swift, plus
EffectsPipelineTests/RenderRequestTests).

Findings:
- Root cause matches the report: the old custom `effectsBlend` CIKernel sampled `original`/`effect`/
  `mask` in one coordinate space via `samplerCoord`, which could vertically reverse Dehaze at full
  amount. Replaced with CIFilter.blendWithAlphaMask() (RenderPipeline.swift:628-653), which is
  coordinate-aware; alpha-only scaling via CIColorMatrix preserves prior partial-amount blend
  semantics (verified amount==1 and amount<1 branches are equivalent to the old mix() formula).
- New `sanitizedDehaze`/`boundedOutput` helpers (RenderPipeline.swift ~579-609) clamp NaN/Inf/out-of-
  range values and crop every intermediate (colorControls output, tone-curve output) back to the
  input extent before it can reach preview, interactive, or export rasterization. This is genuine
  defense-in-depth at the renderer boundary, additive to the pre-existing model-level clamp in
  EffectsAdjustments (didSet) — not a symptom-only fix, and it does not reduce the requested amount.
- cacheVersion bumped 16→17, correctly invalidating stale cached frames for the changed Dehaze path.
- No stray/unrelated tracked-file changes found in the tree (git status clean aside from two
  pre-existing untracked docs unrelated to this issue).

Checks re-run independently:
- `swift test --filter EffectsPipelineTests` — 20/20 passed, including the new
  testDehazeFullRangePreservesOffsetExtentOrientationAndFinitePixels (covers -100/-1/0/+1/+100 on an
  offset 640x400 extent: finite pixels, unchanged extent, no orientation flip).
- `swift test --filter RenderRequestTests` — 5/5 passed, including
  testDehazeFullRangeKeepsPreviewAndExportGeometryAndPixelsAligned (preview/interactive/export
  extent + pixel parity across the same value set).
- `swift test` (full suite) — 600 passed, 13 expected skips, 0 failures.
- `swift build -c release` — clean.
- `git diff --check` — clean.

Acceptance criteria: all four items satisfied and covered by regression tests. No blocker found;
no broader non-blocking findings warranting a child ticket. Verification passes.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T13:14:11.542Z: Independent verification passed: coordinate-aware alpha blend fix confirmed, full test suite (600) + release build clean, no blockers.
