---
id: LUMO-038
title: Implement deterministic resolution-aware photographic grain
type: task
status: done
priority: high
labels:
  - mvp
  - epic:effects
  - phase:6
created: 2026-08-30T18:30:29.865Z
updated: 2026-09-01T05:03:10.795Z
depends_on:
  - LUMO-024
  - LUMO-014
estimate: 8
order: zzzq
board: product
---

## Objective

Add Amount, Size, and Roughness grain that remains visually stable during rerenders and scales appropriately at export.

## Context

Part of **Epic 6 — Photographic effects**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Derive deterministic seed from stable asset/pipeline inputs without changing on slider redraw.
- Use GPU noise synthesis and shape it beyond uniform digital noise.
- Define size in normalized/physical output terms so preview is representative of export.
- Avoid caching random frame-dependent outputs.

## Acceptance criteria

- [ ] Identical source/edit/quality requests reproduce the same grain pattern.
- [ ] Changing unrelated UI state does not make grain dance.
- [ ] Amount, Size, and Roughness are independently measurable.
- [ ] Export grain scale matches the documented viewing-size policy.

## Verification

- Add determinism, parameter-independence, scale, cache-key, and parity tests.

## Out of scope

- Camera-specific film stock emulation.

### Comment — codex @ 2026-09-01T05:00:06.023Z

Implemented in commit a2d8d58. Added Codable/clamped GrainAdjustments (Amount, Size, Roughness), integrated deterministic source-seeded multi-octave GPU value noise after LUT, normalized grain frequency against the output shortest side, threaded the seed through RenderEngine for stable preview/export renders, bumped pipeline cache version to 13, and documented the viewing-size policy. Added determinism, parameter-independence, scale/extent/alpha, post-LUT ordering, cache-key, and preview/export parity coverage. Verification: swift test (455 passed, 24 skipped), swift build -c release, git diff --check, dg validate OK with known unrelated warnings.

### Comment — claude @ 2026-09-01T05:03:08.789Z

### Verification report — counterpoint agent @ 2026-09-01

**Result: PASS.** Independent review of commit a2d8d58 (grain implementation) plus the surrounding pipeline/cache/RenderEngine wiring.

Checked:
- Grain runs after LUT/vignette in the shared `buildImage` funnel, and preview/export/interactive paths all route through the single private `RenderEngine.buildImage`, so the seed (`RenderPipeline.grainSeed(for:)`) is applied consistently — no divergence between preview and export.
- Seed is derived only from `source.cacheFingerprint`, excluding document/quality/scale, so slider drags and unrelated edits cannot perturb the noise field; confirmed by `testGrainIsDeterministicAndSeedIsIndependentOfEditState`.
- Grain params (Amount/Size/Roughness) live in `EditDocument.effects.grain` and flow into `documentHash`, which is part of `PreviewCacheKey` — cache key already separates seed (source-only) from parameters (document-only), so no random/frame-dependent output is ever cached. Verified against `RenderCacheKey.swift`.
- `GrainAdjustments` clamps to finite ranges on init/decode/mutate (checked `.infinity`/`.nan` inputs), Codable round-trips, additive-migration decode default is neutral — matches the project's existing Vignette pattern.
- Size→frequency mapping (48–192 cells/shortest-side) and the "smaller Size ⇒ more/finer cells" direction check out against the shader math and doc.
- Ran `swift build` (clean) and `swift test` (full suite): **455 passed, 24 skipped, 0 failures** — matches the implementer's reported baseline.
- `git status --porcelain` clean aside from pre-existing `.dg` bookkeeping diffs present at session start.

Non-blocking finding filed as a child ticket rather than fixed inline (kernel/shader precision change would perturb the grain field for existing seeds, which needs its own before/after check rather than a drive-by patch during verification):
- **LUMO-081** (labels: `verification`, depends_on: LUMO-038) — `RenderPipeline.applyGrain` passes the `UInt32` seed to the CIKernel as `Float(seed)`; `Float32`'s 24-bit mantissa means seeds within ~256 of each other near 2^32 collide to the same noise field (confirmed: `Float(0xDEADBEEF) == Float(0xDEADBEEF + 100)`). Determinism per-seed is unaffected and no acceptance criterion is literally violated, but it quietly shrinks the effective seed space from 2^32 to ~2^24, which for large libraries can let unrelated images end up with an identical grain pattern.

No blockers. Moving to `done`.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
