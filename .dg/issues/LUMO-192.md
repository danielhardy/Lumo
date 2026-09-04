---
id: LUMO-192
title: Global tone + color statistics analyzer (Tier 0)
type: feature
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:52.506Z
updated: 2026-09-04T14:34:42.194Z
depends_on:
  - LUMO-182
  - LUMO-183
order: zzzzy
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/GlobalToneAnalyzer.swift`
**Depends on:** LUMO-182, LUMO-183
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §4 (Tier 0)

## 1. Problem

Tier 0 (global tone + color statistics) is the only tier that's ever required — Auto must degrade
to it alone if every Vision/mask request fails or is unavailable. It should exist and be solid
before mask-dependent analysis (LUMO-193+) is built, and it works from the canonical
`AnalysisImage` (LUMO-183) with no mask/Vision dependency at all.

## 2. Requirement (acceptance criteria)

1. Computes `ToneStatistics` (both `linear`/`perceptual`, LUMO-182) from an `AnalysisImage` using
   a high-resolution luminance histogram (256 or 512 bins).
2. Luminance definition explicit and documented: `Y = 0.2126R + 0.7152G + 0.0722B`, computed once
   per variant — document the color space each is sampled in, reconciling with whatever
   `Histogram.swift` already assumes for the existing `AutoImageStatistics`.
3. `ColorStatistics` (LUMO-182) computed from the same canonical image, same pass where practical.
4. **No per-pixel Swift loops over large buffers** — reuse `Sources/LumoKit/Models/Histogram.swift`'s
   GPU-backed histogram machinery (`RenderEngine.histogram`) if it can be pointed at the analysis
   image, rather than reimplementing.
5. No `Vision` import — this is the one tier that never depends on masks or Vision.
6. Populates `AnalysisQuality.globalToneAvailable = true` on success; this is the one tier allowed
   to be a hard requirement (a thrown error) rather than soft-degrading.
7. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Reuse `RenderEngine.histogram(...)` rather than a second histogram code path.

## 4. Where to look

- `Sources/LumoKit/Models/Histogram.swift`, `RenderEngine.swift` (`func histogram`).
- `Sources/LumoKit/Models/AutoAdjustment.swift:63-100` — existing percentile/weighted-mean math to
  reuse or adapt.

## 5. Testing

- `Tests/LumoKitTests/GlobalToneAnalyzerTests.swift` (new): synthetic images with hand-computable
  expected percentiles; clipping-fraction correctness for deliberately over/underexposed fixtures.
- Rough timing check against the < 20 ms Tier-0 budget (`docs/PHASE3_SPEC.md` §6) — full benchmark
  infra is LUMO-206.
