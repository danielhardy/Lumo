---
id: LUMO-206
title: Performance instrumentation + benchmark suite
type: task
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:58.504Z
updated: 2026-09-04T14:34:46.591Z
depends_on:
  - LUMO-196
  - LUMO-190
order: zzzzzzzh
board: product
---

**Type:** Task
**Component:** `Tests/LumoKitTests/PhotoAnalysisPerformanceTests.swift` (new) + instrumentation
additions across `Sources/LumoKit/Models/PhotoAnalysis/`
**Depends on:** LUMO-196, LUMO-190
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §6, original proposal §26–28, §43

## 1. Problem

Every analysis/mask ticket was asked to populate `AnalysisTimings` per stage, but nothing yet
enforces the performance budgets in `docs/PHASE3_SPEC.md` §6, and the 768px canonical-image
dimension (left as `// TODO(LUMO-206)` since LUMO-183) is unbenchmarked. This ticket closes both
gaps.

## 2. Requirement (acceptance criteria)

1. `os.signpost`/`Signposter` instrumentation around each major stage (image prep, global tone,
   each mask provider, masked-statistics, assembly) — mostly threading existing `AnalysisTimings`
   capture points into real signposts.
2. Benchmark tests covering: `prepareAnalysisImage()`, `GlobalToneAnalyzer`, each mask provider
   (subject/face/foreground/person), `MaskedToneAnalyzer`, full `.standard` analysis,
   `MaskStore`/`PhotoAnalysisCache` reads (cache-hit path).
3. Baseline + allowed-percentage-regression assertions, not strict ms ceilings (CI variability).
4. Resolve the `// TODO(LUMO-206)` from LUMO-183: benchmark 512/768/1024 canonical dimensions for
   timing + a rough quality signal (does subject detection still succeed); update the default if
   the data supports a different value, otherwise confirm 768 with the numbers that justified it.
5. Confirm measured numbers against `docs/PHASE3_SPEC.md` §6's targets on a representative Apple
   Silicon Mac; record results in the completion comment.
6. Rough transient-memory check that `.standard` analysis stays well under the ~50MB target.
7. Swift 6 clean.

## 3. Implementation notes

- This ticket is explicitly allowed to change `AnalysisConfiguration.maximumDimension`'s default.
- If no benchmark-baseline pattern exists elsewhere in this repo, use a simple "N runs, median,
  compare to a checked-in baseline JSON with allowed % drift" approach.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §6.
- LUMO-183's `AnalysisConfiguration.maximumDimension` TODO.
- Every prior mask-provider/analyzer ticket's `AnalysisTimings` population points.

## 5. Testing

- The benchmark suite itself is the deliverable. Run it, capture numbers, report in the completion
  comment.
