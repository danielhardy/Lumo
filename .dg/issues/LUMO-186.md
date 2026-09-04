---
id: LUMO-186
title: "MaskOperations: invert/intersect/union/subtract/feather/refine"
type: feature
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:50.102Z
updated: 2026-09-04T14:34:40.263Z
depends_on:
  - LUMO-184
order: zzzy
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/MaskOperations.swift`
**Depends on:** LUMO-184
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` (revised mask-foundation sequencing)

## 1. Problem

Both Auto's regional statistics (LUMO-193) and the eventual Masking UI (LUMO-201) need to combine
masks — Auto might need "background" as "everything not `.subject`"; a user might combine
"person" and "subtract face" to mask clothing only. This logic belongs in one shared module, not
reimplemented once inside `PhotoAnalysis` and again inside the Masking UI.

## 2. Requirement (acceptance criteria)

1. `enum MaskOperations` (or a small set of free functions/methods on `RegionMask`) providing:
   - `invert(_:) -> RegionMask`
   - `intersect(_:_:) -> RegionMask`
   - `union(_:_:) -> RegionMask`
   - `subtract(_:from:) -> RegionMask`
   - `feather(_:radius:) -> RegionMask` (soft edge, for compositing/local-adjustment use)
   - `refine(_:) -> RegionMask` (placeholder hook for LUMO-202's higher-quality refinement —
     this ticket can implement a basic version, e.g. edge cleanup, and leave the full tile-based
     upgrade to LUMO-202)
2. Operations compose: `subtract(faceMask, from: personMask)` should produce a valid `RegionMask`
   at a sensible output quality/resolution (document the resolution rule — e.g. result quality is
   the minimum of the inputs' qualities, since you can't get more precision than your least-
   precise input).
3. Every operation works purely on `RegionMask` + whatever pixel access `MaskStore` (LUMO-185)
   exposes — no Vision, no `AnalysisImage` re-render.
4. Output masks are written through `MaskStore` like any other mask (consistent caching, not a
   parallel "computed mask" concept that bypasses the store).
5. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- This is exactly the kind of module that benefits from being genuinely generic over pixel data
  rather than tied to any specific `SemanticMaskKind` — a composed mask (e.g. "person minus face")
  doesn't map cleanly onto the semantic-kind enum, so give composed results their own identity
  (e.g. a `RegionMask` with `kind` describing the composition, or a separate lightweight
  `kind: .derived`/similar) rather than forcing them into `SemanticMaskKind`'s cases.
- Feathering in particular needs a real, GPU-appropriate implementation (Core Image blur on the
  mask channel is the obvious tool) — avoid a per-pixel Swift loop, same "no per-pixel Swift loops
  over large buffers" rule as the tone analyzer.

## 4. Where to look

- LUMO-184 — `RegionMask`, `SemanticMaskKind`, `MaskQuality`.
- LUMO-185 — `MaskStore`, where operation results get cached.
- `Sources/LumoKit/Models/LUTFilterCache.swift` — existing precedent for GPU-backed cached
  transforms, useful as a shape reference even though the domain differs.

## 5. Testing

- `Tests/LumoKitTests/MaskOperationsTests.swift` (new): each operation against synthetic masks
  with known overlap (e.g. two half-image masks — assert intersect/union/subtract produce exactly
  the expected coverage). Feather test: assert edge softness increases with radius (e.g. compare
  gradient steepness at the mask boundary before/after). Composition test: chain 2–3 operations
  and assert the result is still a valid, cacheable `RegionMask`.
