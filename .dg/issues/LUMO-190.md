---
id: LUMO-190
title: Foreground instance + background mask provider
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:51.702Z
updated: 2026-09-04T14:34:41.546Z
depends_on:
  - LUMO-187
  - LUMO-185
order: zzzzv
board: product
---

**Type:** Feature
**Component:** `Sources/LumoKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift`
(+`.foregroundInstance`/`.background`)
**Depends on:** LUMO-187, LUMO-185
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §4 (Tier 2)

## 1. Problem

Saliency (LUMO-188) says *where* attention likely is; foreground instance masking says *which
concrete object(s)* can be separated from the background, with real pixel masks. This is the
heaviest of the core mask kinds. `.background` is derived from it (everything not covered by any
foreground instance) — both kinds ship together since one is naturally the complement of the
other.

## 2. Requirement (acceptance criteria)

1. Implement `mask(for: .foregroundInstance(i), image:, quality:)` using Apple's foreground
   instance mask request, producing one or more real pixel-mask `RegionMask`s (never a bounding
   box — Vision returns actual masks here, use them).
2. Implement `mask(for: .background, image:, quality:)` as the complement of the union of all
   detected foreground instances (use `MaskOperations.invert`/`union` from LUMO-186 rather than a
   separate ad-hoc computation).
3. Masks written through `MaskStore` (LUMO-185), keyed consistently.
4. Failure/unsupported throws a typed, catchable error.
5. Coordinates via LUMO-183; Vision revision recorded in `VisionConfiguration`.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- This is the heaviest analyzer here — pay attention to `AnalysisTimings.foregroundMasking`
  against the `.detailed`-level budget in `docs/PHASE3_SPEC.md` §6 (< 300 ms); if it's blowing the
  budget on a representative fixture, say so in the PR (LUMO-206 owns the formal benchmark suite,
  but don't ship something wildly over budget unmeasured).
- Always prefer the real pixel mask Vision returns over any bounding rectangle it also provides.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §4, §6.
- LUMO-186's `MaskOperations` — for deriving `.background`.

## 5. Testing

- `Tests/LumoKitTests/ForegroundMaskProviderTests.swift` (new): synthetic fixture with a clear
  separable foreground object — assert at least one `.foregroundInstance` mask with roughly
  expected coverage, and a `.background` mask that's its complement (assert coverage sums to
  ~1.0). No-clear-foreground fixture — assert empty, not an error. Failure path.
