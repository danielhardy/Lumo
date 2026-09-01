---
id: LUMO-033
title: Implement three-way Color Grading with blending and balance
type: task
status: done
priority: high
labels:
  - mvp
  - epic:color
  - phase:5
created: 2026-08-30T18:30:28.143Z
updated: 2026-08-31T21:00:29.195Z
depends_on:
  - LUMO-024
estimate: 8
order: a0
board: product
commits:
  - d342a92
---

## Objective

Add shadows, midtones, and highlights hue/saturation wheels plus Blending and Balance.

## Context

Part of **Epic 5 — White balance, mixer, and color grading**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define compact Codable model with neutral semantics.
- Implement luminance-weighted GPU application with smooth tonal overlap.
- Make balance shift tonal regions and blending control overlap predictably.
- Keep stage order versioned relative to mixer/effects/LUT.

## Acceptance criteria

- [ ] Each wheel predominantly affects its intended tonal region.
- [ ] Blending and Balance have independent, monotonic effects.
- [ ] Zero saturation across all wheels is identity regardless of hue.
- [ ] No visible discontinuity appears on a smooth grayscale gradient.

## Verification

- Add tonal-region, identity, gradient-continuity, and parity tests.

## Out of scope

- Channel curves.
- Local grading masks.

### Comment — codex @ 2026-08-31T20:58:17.227Z

Implemented in commit 8742d9e. Added Codable ColorGradingAdjustments with Shadows/Midtones/Highlights wheels, Blending, and Balance; integrated a single smooth luminance-weighted Core Image GPU kernel after the HSL mixer and before ordered effects/LUT; bumped cache version to 9; added persistence, identity, tonal-region, monotonic blend/balance, gradient-continuity, shared-graph, and preview/export parity coverage. Verification: swift test passed (412 tests, 21 expected skips), swift build -c release passed, git diff --check passed, dg validate passed with only pre-existing warnings.

### Comment — claude @ 2026-08-31T21:00:26.811Z

## Verification report — counterpoint pass (independent re-review)

Scope: full re-derivation of the render-math correctness, not just re-running the prior test suite.

**Checks performed**
- `swift build` (debug) and `swift build -c release`: clean, no new warnings.
- `swift test` (full suite): 412 passed, 21 expected skips, 0 failures.
- `swift test --filter ColorGradingTests`: 7/7 passed.
- `git diff --check`: clean.
- Manual trace of the GPU kernel math (`RenderPipeline.applyColorGrading` / `colorGradingKernelSource`):
  - At `blending=100`, `shadowEdge` (0.58) crosses above `highlightEdge` (0.42) — verified algebraically that `shadowWeight + midtoneWeight + highlightWeight = 1 + highlightStep·(1 − shadowStep) ≥ 1` for all inputs, so the crossover never produces a zero/near-zero `weightTotal` divide and normalization keeps the blend continuous. Not a bug — the crossover is how the overlap widens.
  - `balance` shifts only the luminance sample used for region classification (`shiftedLuminance`), not the luminance used to compute each wheel's target hue color — this keeps balance's effect on region weighting independent of the wheel colors themselves, consistent with "independent, monotonic effects."
  - Zero-saturation identity, tonal-region dominance, and gradient continuity are all exercised by dedicated tests with concrete pixel assertions, not just structural checks.
- Confirmed `cacheVersion` bump to 9 is wired through `RenderEngine` and `Thumbnails` cache keys, so cached renders correctly invalidate on upgrade.
- Confirmed stage placement: HSL mixer → grading → ordered effects/LUT, matching `docs/COLOR_MODEL.md` and the scope requirement to keep stage order versioned.

**Finding (fixed inline, non-blocking)**
- `ColorGradingChannel` type alias (`Sources/LumoKit/Models/ColorGradingAdjustments.swift`) had zero callers anywhere in `Sources/` or `Tests/` — dead speculative API surface. Removed as a localized, behavior-preserving cleanup in commit d342a92. Rebuilt and reran the full suite (412 passed) after the change to confirm no regression.

**Verdict:** PASS. All four acceptance criteria are met and independently re-verified against the actual kernel math, not just the test names. No blockers.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T21:00:29.193Z: Independent verification passed: build/tests clean, kernel math traced and confirmed correct, one dead-code cleanup applied (d342a92).
