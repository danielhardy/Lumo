---
id: LUMO-172
title: "Audit: avoid materializing uncacheable high-resolution intermediates"
type: task
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - performance
  - memory
  - rendering
  - audit
created: 2026-09-03T23:31:00.000Z
updated: 2026-09-04T07:20:03.062Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Estimated byte cost is checked before allocating a full-frame materialized intermediate.
      result: pass
      notes: RenderEngine.materializedImage computes a MaterializationEstimate (rowBytes/cpuBytes/gpuBytes via overflow-checked multiplication) and compares estimate.workingSetBytes against maxWorkingSetBytes before the Data(repeating:count:) bitmap allocation or context.render call; on over-budget it increments materializationBudgetSkipCount and returns nil without allocating.
    - criterion: Above-budget images use a documented tiled, ROI, fused, or explicitly non-cached path.
      result: pass
      notes: processingPrefix() returns nil (caller keeps the original fused lazy graph) when materializedImage is rejected; the interactive RAW session's materialize closure likewise falls back to the lazy image; settled RAW development returns the request-local lazy `image` instead of inserting it into developedSourceCache. Documented in docs/RENDER_MEMORY_BUDGET.md.
    - criterion: CPU and GPU working-set accounting is included in the relevant memory budget.
      result: pass
      notes: MaterializationEstimate.workingSetBytes sums cpuBytes (retained Data backing store) and gpuBytes (estimated same-size RGBA16Float texture) with saturating arithmetic; developedSourceMaxCostBytes/processingPrefixMaxCostBytes in RenderCacheConfiguration are documented as working-set budgets covering both terms.
    - criterion: Regression coverage verifies no repeated above-budget materialization storm for large standard and RAW sources.
      result: pass
      notes: RenderCacheTests.testAboveBudgetStandardPrefixStaysFusedWithoutMaterializationStorm (3000x2000 source, 64MB prefix budget, 3 edits) asserts processingPrefixMaterializations == 0 and materializationBudgetSkips == 3. testAboveBudgetRAWSessionDoesNotMaterializeOnEveryEdit covers the RAW session equivalently, opt-in via Fixtures.localRAWURL per existing slow-lane policy (skipped locally, no fixture present).
    - criterion: Render output parity is maintained for supported image sizes.
      result: pass
      notes: Existing prefix/cache pixel-parity tests (e.g. testCachedPrefixPreservesDownstreamCropGrainAndLUTPixels) still pass unchanged; the estimate/budget gate only changes admission, not the render path taken for in-budget sizes, and the fused fallback for above-budget sizes reuses the same RenderPipeline graph construction used before caching, so no separate/alternate pixel path was introduced.
  checks_run:
    - swift build (debug)
    - swift test --filter RenderCacheTests (21 run, 20 passed, 1 skipped - no local RAW fixture)
    - "swift test (full suite: 740 passed, 33 skipped, 0 failures)"
    - dg validate (OK; pre-existing unrelated warnings only)
    - git diff --check (clean)
    - manual read of RenderEngine.swift/BoundedCache.swift/RenderEngineResources.swift diff and docs/RENDER_MEMORY_BUDGET.md
  findings:
    - "Low-severity/cosmetic: materializationEstimate's gpuBytes overflow guard is unreachable because gpuBytes uses the identical pixels*8 multiplication already guarded by the preceding cpuBytes overflow check; workingSetBytes still saturates correctly since cpuBytes == gpuBytes here. Not blocking, not worth a backlog ticket."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T07:20:03.059Z
  session: 01MTMMFSIO80D7VEW1
---

## Objective

Avoid expensive full-frame materialization when an intermediate cannot fit in its bounded cache.

## Context

The render engine materializes RGBA-half buffers before inserting them into caches capped at 256 MB. A 40 MP image is already about 320 MB and is therefore rendered and allocated only to be rejected. RAW and pre-LUT paths can repeat this work on later edits, with additional Metal texture memory increasing transient pressure.

## Acceptance criteria

- [ ] Estimated byte cost is checked before allocating a full-frame materialized intermediate.
- [ ] Above-budget images use a documented tiled, ROI, fused, or explicitly non-cached path.
- [ ] CPU and GPU working-set accounting is included in the relevant memory budget.
- [ ] Regression coverage verifies no repeated above-budget materialization storm for large standard and RAW sources.
- [ ] Render output parity is maintained for supported image sizes.


### Comment — codex @ 2026-09-04T07:17:15.635Z

Implemented in 35c9da3. Render intermediate admission now estimates RGBA-half CPU plus GPU working-set bytes with saturating arithmetic before allocation; above-budget processing prefixes stay fused/non-cached, and above-budget RAW outputs remain request-local instead of entering the settled cache. Added docs/RENDER_MEMORY_BUDGET.md and standard/RAW materialization-storm regressions (RAW test follows the existing opt-in local-fixture policy). Verified: swift test (740 passed, 33 skipped), focused above-budget tests (1 standard passed, 1 RAW skipped without fixture), swift build -c release, git diff --check, dg validate. Repository-wide format script still reports pre-existing violations in already-modified files; direct strict lint passes for the newly touched resource/cache files.

## Agent log

- 2026-09-04T07:20:03.061Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Estimated byte cost is checked before allocating a full-frame materialized intermediate. (pass) — RenderEngine.materializedImage computes a MaterializationEstimate (rowBytes/cpuBytes/gpuBytes via overflow-checked multiplication) and compares estimate.workingSetBytes against maxWorkingSetBytes before the Data(repeating:count:) bitmap allocation or context.render call; on over-budget it increments materializationBudgetSkipCount and returns nil without allocating.
- [x] Above-budget images use a documented tiled, ROI, fused, or explicitly non-cached path. (pass) — processingPrefix() returns nil (caller keeps the original fused lazy graph) when materializedImage is rejected; the interactive RAW session's materialize closure likewise falls back to the lazy image; settled RAW development returns the request-local lazy `image` instead of inserting it into developedSourceCache. Documented in docs/RENDER_MEMORY_BUDGET.md.
- [x] CPU and GPU working-set accounting is included in the relevant memory budget. (pass) — MaterializationEstimate.workingSetBytes sums cpuBytes (retained Data backing store) and gpuBytes (estimated same-size RGBA16Float texture) with saturating arithmetic; developedSourceMaxCostBytes/processingPrefixMaxCostBytes in RenderCacheConfiguration are documented as working-set budgets covering both terms.
- [x] Regression coverage verifies no repeated above-budget materialization storm for large standard and RAW sources. (pass) — RenderCacheTests.testAboveBudgetStandardPrefixStaysFusedWithoutMaterializationStorm (3000x2000 source, 64MB prefix budget, 3 edits) asserts processingPrefixMaterializations == 0 and materializationBudgetSkips == 3. testAboveBudgetRAWSessionDoesNotMaterializeOnEveryEdit covers the RAW session equivalently, opt-in via Fixtures.localRAWURL per existing slow-lane policy (skipped locally, no fixture present).
- [x] Render output parity is maintained for supported image sizes. (pass) — Existing prefix/cache pixel-parity tests (e.g. testCachedPrefixPreservesDownstreamCropGrainAndLUTPixels) still pass unchanged; the estimate/budget gate only changes admission, not the render path taken for in-budget sizes, and the fused fallback for above-budget sizes reuses the same RenderPipeline graph construction used before caching, so no separate/alternate pixel path was introduced.
Checks run:
- swift build (debug)
- swift test --filter RenderCacheTests (21 run, 20 passed, 1 skipped - no local RAW fixture)
- swift test (full suite: 740 passed, 33 skipped, 0 failures)
- dg validate (OK; pre-existing unrelated warnings only)
- git diff --check (clean)
- manual read of RenderEngine.swift/BoundedCache.swift/RenderEngineResources.swift diff and docs/RENDER_MEMORY_BUDGET.md
Findings:
- Low-severity/cosmetic: materializationEstimate's gpuBytes overflow guard is unreachable because gpuBytes uses the identical pixels*8 multiplication already guarded by the preceding cpuBytes overflow check; workingSetBytes still saturates correctly since cpuBytes == gpuBytes here. Not blocking, not worth a backlog ticket.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTMMFSIO80D7VEW1
Summary: Verified: byte-cost admission check gates materialization before allocation, over-budget paths stay fused/non-cached (documented), CPU+GPU working-set accounting is in the budget, regression tests cover standard and RAW materialization storms, and parity tests still pass. Full suite: 740 passed/33 skipped/0 failures.
