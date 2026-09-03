---
id: LUMO-036
title: Implement distinct Texture, Clarity, and Dehaze stages
type: task
status: done
priority: high
labels:
  - mvp
  - epic:effects
  - phase:6
created: 2026-08-30T18:30:29.106Z
updated: 2026-09-01T04:43:14.095Z
depends_on:
  - LUMO-024
estimate: 8
order: a0
board: product
commits:
  - 44c6b8a
---

## Objective

Create three photographically useful GPU-backed operations rather than variants of one contrast slider.

## Context

Part of **Epic 6 — Photographic effects**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Texture targets medium/high-frequency detail with limited tone shift.
- Clarity targets local midtone contrast.
- Dehaze combines local contrast/tone/color behavior for haze perception.
- Normalize scale-sensitive radii across preview and export.

## Acceptance criteria

- [ ] Frequency/tone tests distinguish all three controls.
- [ ] Neutral is identity and negative values produce sensible inverse effects.
- [ ] No halos or clipping become objectionable at moderate settings on validation images.
- [ ] Interactive implementation contains no per-pixel Swift loop.

## Verification

- Add frequency-pattern, tonal-region, extent, parity, and visual quality tests.

## Out of scope

- AI atmospheric correction.

### Comment — codex @ 2026-09-01T04:41:21.475Z

Implemented in commit 44c6b8a. Added Codable/clamped EffectsAdjustments (Texture, Clarity, Dehaze), integrated a GPU-only shared Core Image stage with distinct spatial/tonal/color behavior and extent-relative radii, updated document identity/comparison/cache versioning, and added frequency, tonal, inverse, alpha/extent, scale, persistence, and preview/export parity coverage. Checks: swift test (443 passed, 24 expected skips), swift build -c release, git diff --check, dg validate (pre-existing warnings only).

### Comment — claude @ 2026-09-01T04:43:11.211Z

### Independent verification — claude @ 2026-09-01T04:43:11.000Z

**Verdict: PASS.** Re-ran all declared checks independently and reviewed the diff for correctness, maintainability, security, and performance.

**Reproduced checks**
- `swift test`: 443 passed, 24 expected skips, 0 failures.
- `swift build -c release`: clean.
- `git diff --check`: clean.
- `dg validate`: OK (only pre-existing, unrelated warnings — agents.pickup.runner model name, LUMO-035 context completeness).

**Code review findings**
- Texture/Clarity/Dehaze are genuinely distinct GPU graphs (different radii, masks, and tonal/color terms), matching the frequency-pattern and tonal-region tests added in `Tests/LumoKitTests/EffectsPipelineTests.swift`.
- `EffectsAdjustments.isIdentity` short-circuits `applyEffects` for the neutral case (common path), and neutral is verified as an exact no-op (`testNeutralEffectsAreAnExactIdentity`).
- Negative values reuse the same neighbourhood radius as a softening/blur operation rather than a global blur, keeping the inverse direction sensible and photographically restrained (coefficients capped around 0.14–0.95 at full amount).
- Radii are normalized as a fraction of the image's shortest side (`normalizedRadius`), verified by `testEffectsUseRelativeRadiiAtPreviewScale` to hold 2x scale parity between preview and full-size renders.
- No per-pixel Swift loop — texture/clarity/dehaze are entirely CIFilter/CIKernel/CIColorKernel graphs, satisfying the acceptance criterion directly.
- `EditDocument` migration is additive and backward compatible (decodeIfPresent defaulting to `.neutral`), `cacheVersion` bumped to 11, `originalForComparison`/`isComparisonAvailable`/`isIdentity` all updated consistently.
- No UI wiring for these controls yet — confirmed intentional: LUMO-039 (Effects inspector) depends on this issue and is scoped to expose Texture/Clarity/Dehaze in the UI.
- No blocking issues found; no localized fixes were necessary.

Clearing lease and moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T04:43:14.093Z: Independent verification passed: swift test (443/0 failures), swift build -c release, git diff --check, dg validate all clean. Texture/Clarity/Dehaze confirmed distinct GPU-only graphs with identity/inverse behavior; no blockers found.
