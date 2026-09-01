---
id: LUMO-031
title: Harden Vibrance and Saturation as distinct global color controls
type: task
status: done
priority: high
labels:
  - mvp
  - epic:color
  - phase:5
created: 2026-08-30T18:30:27.428Z
updated: 2026-08-31T20:37:53.851Z
depends_on:
  - LUMO-024
estimate: 3
order: a0
board: product
---

## Objective

Ensure saturation and vibrance have photographer-useful, distinct behavior and correct -100/0/+100 mapping.

## Context

Part of **Epic 5 — White balance, mixer, and color grading**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Map UI values to stable normalized engine values.
- Keep saturation neutral exact and -100 near monochrome.
- Verify vibrance protects already-saturated colors/skin better than uniform saturation.
- Preserve color space and alpha.

## Acceptance criteria

- [ ] Saturation -100 is near-monochrome within tolerance.
- [ ] Vibrance and saturation produce measurably distinct changes on mixed-chroma input.
- [ ] Neutral values are no-ops and preview/export agree.
- [ ] Outputs remain finite and gamut handling is documented.

## Verification

- Add synthetic swatch and representative skin/foliage property tests.

## Out of scope

- Selective masking.

### Comment — codex @ 2026-08-31T20:35:47.903Z

Implemented in commit 716ac6a. Added Codable/Equatable/Sendable ColorAdjustments with finite clamped -100...+100 UI values and stable normalization (Saturation → 0...2, Vibrance → -1...+1); integrated global Color after Light and before legacy adjustments; preserved legacy nodes, alpha, working-space output, preview/export shared rendering, and comparison baseline behavior; bumped RenderPipeline.cacheVersion to 7; documented gamut handling. Added synthetic skin/foliage/primary/neutral swatch coverage for near-monochrome -100 saturation, distinct vibrance protection, neutral identity, finite output, alpha preservation, graph reachability, persistence, migration, and mapping. Verification: swift test passed (397 executed, 21 expected skips), swift build -c release passed, git diff --check passed, dg validate OK with only pre-existing runner-model and LUMO-029 context warnings.

### Comment — claude @ 2026-08-31T20:37:50.095Z

Verification report (independent counterpoint review, post-human-review):

Scope: reviewed commit 716ac6a (ColorAdjustments.swift, EditDocument.swift, RenderPipeline.swift, AppViewModel.swift, docs/COLOR_MODEL.md) plus the new ColorAdjustmentsTests.swift and ColorPipelineTests.swift against the acceptance criteria.

Correctness:
- Mapping is exact and documented: vibrance -100...100 -> CIVibrance.inputAmount -1...1; saturation -100...100 -> CIColorControls.inputSaturation 0...2 (neutral = 1, exact identity at 0). Confirmed by testNeutralValuesAndNormalizedMapping.
- Neutral is an exact no-op (applyColor short-circuits on isIdentity; testNeutralColorIsAnExactNoOpAndPreservesAlpha) and reaches the shared render graph identically for preview/export (single RenderPipeline.buildImage path, no separate preview-only code path).
- Saturation -100 verified near-monochrome (chroma <= 3/255) on skin/foliage/saturated-primary swatches.
- Vibrance vs. saturation produce measurably distinct output on mixed-chroma input, and vibrance is shown to protect the already-saturated primary swatch more than uniform saturation (testVibranceAndSaturationHaveDistinctBehaviorOnMixedChromaInput).
- Inputs are finite-clamped at construction and mutation (didSet), including +-infinity/NaN; extremes checked finite post-render via RGBAf readback.
- Alpha and colour-space metadata preserved (Core Image node, no CPU pixel loop); explicit alpha-preservation test at 0.4 alpha.
- Migration is additive: `color` missing on an older document decodes to `.neutral`; `originalForComparison` strips `color` like `light`; `RenderPipeline.cacheVersion` bumped 6->7 so cached graphs don't silently miss the new stage.
- Gamut handling is documented in docs/COLOR_MODEL.md (out-of-gamut values left in the lazy graph, clipped by the requested WorkingSpace output format, shared by preview/export).

Checks run independently (not just re-trusting the implementer's log):
- `swift test` (full suite): 397 tests, 21 expected skips, 0 failures.
- `swift build` (debug) and `swift build -c release`: both clean.
- `git diff --check`: clean.
- `dg validate`: OK, only the same pre-existing warnings noted in the implementation comment (runner-model name, LUMO-029 context completeness) — unrelated to this change.

Design note (non-blocking, not a defect): the new global `ColorAdjustments` stage coexists with the pre-existing legacy `AdjustmentNode` `.vibrance`/`.saturation` slots (applied later in the graph). This mirrors the established Light/legacy-adjustments precedent from LUMO-028/030 and has no UI exposure yet — LUMO-034 (Ship responsive Color, Mixer, and Grading inspector sections) owns wiring the Color inspector UI and depends on this issue, so no user-facing double-control exists today. No action needed on this ticket.

No blockers found. No child tickets filed. No source changes made during verification (read-only checks + test/build runs only).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T20:37:53.651Z: Independent verification passed: mapping, near-monochrome -100 saturation, distinct vibrance/saturation behavior, finite/alpha-preserving output, and additive migration all confirmed; swift test (397/0 fail), swift build (debug+release), git diff --check, and dg validate all clean. No blockers, no child tickets.
