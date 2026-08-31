---
id: LUMO-025
title: Refine Exposure, Contrast, Highlights, and Shadows behavior
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:light
  - phase:4
created: 2026-08-30T18:30:25.335Z
updated: 2026-08-31T19:37:10.031Z
depends_on:
  - LUMO-024
estimate: 5
order: a0
board: product
commits:
  - 8934fee
---

## Objective

Make the inherited controls photographically sensible and distinct using GPU-backed Core Image/Metal operations.

## Context

Part of **Epic 4 — Photographic Light controls**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Keep exposure approximately EV-based.
- Make contrast alter separation without immediate endpoint clipping.
- Localize highlights to upper tones and shadows to lower tones.
- Avoid CPU per-pixel loops.

## Acceptance criteria

- [ ] +1 Exposure measurably approximates one-stop brightening on a linear test ramp.
- [ ] Highlights affect upper luminance more than shadows; Shadows show the inverse.
- [ ] Moderate contrast preserves usable endpoints.
- [ ] Interactive and export results are directionally/perceptually consistent.

## Verification

- Add numeric-region property tests and visual samples for highlight, shadow, and underexposed scenes.

## Out of scope

- Camera-specific Adobe matching.

### Comment — codex @ 2026-08-31T19:33:13.613Z

Implemented in commit 64a8f01. Refined the shared GPU Light stage to use native EV exposure plus a gamma-aware fixed-endpoint CIToneCurve for distinct contrast, highlights, and shadows; added linear-ramp property tests, visual XCTest samples, Light-aware preview/export parity coverage, and bumped RenderPipeline.cacheVersion to 3. Verification: swift test passed (363 tests, 20 expected skips), swift build -c release passed, git diff --check passed, dg validate passed with only pre-existing warnings.

### Comment — claude @ 2026-08-31T19:37:05.213Z

Independent verification: PASS, with one correctness fix applied.

**Reviewed:** commit 64a8f01 (applyLight EV + 5-point CIToneCurve mapping for Contrast/Highlights/Shadows).

**Bug found and fixed (commit 8934fee):** the interior tone-curve points were computed independently per-control with no ordering guarantee. For contrast=-100, highlights=-100, shadows=+100 (a plausible edit: flatten contrast, lift shadows, protect highlights), the raw points came out [0, 0.52, 0.50, 0.48, 1.0] — monotonically *decreasing* through the mid-to-highlight region. CIToneCurve does not enforce monotonicity, so this rendered as a local tone inversion rather than a smooth curve, violating the 'photographically sensible' and 'directionally consistent' acceptance criteria for combined slider use. Verified numerically (Python model of the formula) before touching Swift.

**Fix:** clamp each interior point to be >= the previous point (running max) before handing them to CIToneCurve. This is a localized, testable fix — same intended mapping when values are already well-ordered, monotonic in every case otherwise. Bumped `RenderPipeline.cacheVersion` 3 → 4 per the documented invalidation rule, since affected documents now render different pixels with an unchanged schema. Updated `docs/LIGHT_MODEL.md` to match. Added `testCombinedLightControlsStayMonotonic` regression test targeting the exact crossing case.

**Checks run:**
- `swift test`: 365 tests (363 + 2 net new incl. the regression test), 20 expected skips, 0 failures.
- `swift build -c release`: passed.
- `git diff --check`: clean.
- `dg validate`: OK, only pre-existing warnings (agents.pickup.runner model name, LUMO-023 context completeness).

**Other acceptance criteria spot-checked and holding:** +1 EV ~doubles a linear midtone sample (native CIExposureAdjust, unaffected by the fix); Highlights/Shadows remain tonal inverses; moderate contrast (50) preserves ramp endpoints within 0.01; GPU-only graph (CIExposureAdjust + CIToneCurve, no CPU per-pixel loop) confirmed by reading applyLight.

**Non-blocking finding filed separately:** LUMO-066 (backlog, `verification` label, parent LUMO-025) — `LightAdjustments.existingNodeRepresentation` is now dead code (zero callers repo-wide) despite a doc comment claiming it's kept for migration/diagnostic use. Cleanup only, not folded into this fix to keep it minimal.

Clearing lease and moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T19:37:10.030Z: Independent verification passed after fixing a tone-curve monotonicity bug (contrast/highlights/shadows combined values could invert tones locally). Fix + regression test in 8934fee. Non-blocking cleanup filed as LUMO-066.
