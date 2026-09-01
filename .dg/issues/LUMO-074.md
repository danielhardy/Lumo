---
id: LUMO-074
title: Capture measured before/after benchmark for tone-curve kernel replacement
type: task
status: done
priority: low
labels:
  - verification
created: 2026-08-31T23:22:31.174Z
updated: 2026-09-01T00:00:46.826Z
depends_on:
  - LUMO-071
order: a0
board: product
---

Parent: LUMO-071 (verification finding, non-blocking)

## Context

LUMO-071 replaced the per-render 64³ `CIColorCube` tone-curve construction with an
actor-confined 256×1 texture + Core Image kernel (commit c459816, verification fix e6617d8).
The acceptance criteria for LUMO-071 called for measured benchmarks — graph construction cost,
bytes allocated/uploaded, GPU render time, and end-to-end pointer-to-present latency, before vs.
after — showing a material win. The implementation comment only asserts the theoretical byte
reduction (~4 KiB vs ~4 MiB) and cites `swift test`/`swift build` passing; no profiling run or
recorded numbers exist in the repo.

The architectural win is not in doubt (per-tick cube construction/upload is categorically gone),
so this was not treated as a blocker. But the acceptance criterion for an actual measurement is
still open.

## Scope

- Add a lightweight benchmark (in the style of `Tests/LumoKitTests/PreviewCostBenchmark.swift`)
  that measures per-tick allocation/time for `RenderPipeline.applyToneCurve` / `ToneCurveFilterCache`
  under a curve drag, and records before/after numbers (the "before" cube path can be reconstructed
  from git history at c459816^ if needed for a comparison run).
- Record the result in `docs/LIGHT_MODEL.md` or `docs/CODE_REVIEW.md`.

## Acceptance

- [ ] A measured (not theoretical) before/after comparison exists for bytes allocated/uploaded
  and per-tick timing.
- [ ] The result is written down somewhere durable (doc or benchmark test asserting a bound).


### Comment — codex @ 2026-08-31T23:59:19.713Z

Added an opt-in PreviewCostBenchmark that reconstructs the pre-LUMO-071 64³ CIColorCube baseline, drives 30 changing curve values, and forces 1024×768 GPU rasterization against the cached 256×1 kernel path. Recorded the captured before/after result in docs/LIGHT_MODEL.md: 4,194,304 → 4,096 bytes per tick and 85.40 → 3.31 ms/tick (25.8×). Verification: targeted benchmark passed, swift test passed (427 tests, 24 expected skips), swift build -c release passed, and git diff --check passed. Commit: 41c99cf


### Comment — claude @ 2026-09-01T00:00:44.201Z

## Verification report (counterpoint agent, sonnet)

**Verdict: PASS**

Checked commit 41c99cf against the acceptance criteria and the LUMO-071 finding it addresses.

- **Benchmark correctness**: `testMeasureToneCurveDragCost` reconstructs the pre-LUMO-071 64³
  `CIColorCube` path faithfully (matches `c459816^`'s cube construction) and drives the current
  path through `RenderPipeline.applyLight(LightAdjustments(toneCurve:), to:, cache:)`, which is
  confirmed to route into `applyToneCurve`/`ToneCurveFilterCache.apply` (RenderPipeline.swift:234).
  Both arms force GPU rasterization via `CIContext.createCGImage`, so the comparison is apples-to-
  apples (graph build + upload + render, not just graph construction).
- **Curve varies every tick** (`dragCurve(tick:ticks:)`), so `ToneCurveFilterCache`'s
  equality-gated cache (curve != nextCurve) correctly misses on every iteration — this matches
  real drag behavior rather than accidentally measuring a warm-cache no-op.
- **Byte figures are exact**, not estimates: 64³×4×4B = 4,194,304 vs 256×4×4B = 4,096, matching the
  doc and the actual `Data` payload sizes in both code paths.
- **Reran the benchmark locally**: `LUMO_BENCH=1 swift test --filter
  PreviewCostBenchmark.testMeasureToneCurveDragCost` passes and reproduces the effect (this run:
  57.12 → 2.36 ms/tick, 24.2×; doc's captured run: 85.40 → 3.31 ms/tick, 25.8×). Absolute ms varies
  run-to-run as expected for a wall-clock micro-benchmark; the doc already scopes its numbers to
  "captured on 2026-08-31, this checkout" rather than claiming a universal constant — appropriate
  caveat, not a defect.
- **Full suite**: `swift build`, `swift test` (427 tests, 24 expected skips, 0 failures), and
  `swift build -c release` all pass.
- **Doc**: `docs/LIGHT_MODEL.md` records the measured before/after table and the exact command to
  reproduce it. Both acceptance boxes are satisfiable from this evidence.
- **Tree**: no unreviewed source changes found; git status matches the pre-existing DispatchGraph
  bookkeeping state only.

No blocking or non-blocking findings. No fixes applied, no child tickets created.

## Agent log

- 2026-09-01T00:00:46.824Z: Verified: benchmark and doc are correct, reproducible, and satisfy both acceptance criteria; no findings
