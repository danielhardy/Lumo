---
id: LUMO-188
title: Attention saliency -> subject mask provider
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:50.916Z
updated: 2026-09-04T14:34:40.912Z
depends_on:
  - LUMO-187
  - LUMO-185
order: zzzzh
board: product
---

**Type:** Feature
**Component:** `Sources/LumoKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift` (+`.subject`)
**Depends on:** LUMO-187, LUMO-185
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §4 (Tier 1)

## 1. Problem

The first real semantic mask: "where is the visually important subject?", via attention-based
saliency. This is the lowest-cost, highest-value signal and should land before face/foreground so
later tickets have at least one real mask to test against.

## 2. Requirement (acceptance criteria)

1. Implement `VisionSemanticMaskProvider.mask(for: .subject, image:, quality:)` using Apple's
   attention-based saliency request, converting the resulting heat map into a `RegionMask`.
2. At `.analysis` quality this runs against the canonical ~768px `AnalysisImage`; document what
   `.preview`/`.render` mean for this kind (saliency itself may not need a higher-resolution pass
   — if so, say so explicitly and have those quality levels resolve to the same underlying
   computation, rather than silently ignoring the requested quality).
3. Coordinates converted through LUMO-183's single conversion function.
4. Result written through `MaskStore` (LUMO-185), keyed correctly.
5. Failure (unsupported hardware, request error, no salient region) throws a typed, catchable
   error rather than crashing — the *caller* (LUMO-193/195) decides whether that's fatal or
   degrades gracefully; this ticket's job is just to fail cleanly and predictably.
6. Vision revision recorded in `VisionConfiguration` (LUMO-187).
7. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Keep the request/response mapping small and dumb — turning this into "the" primary subject with
  confidence scoring is LUMO-197/198's job, not this ticket's. This ticket only needs to answer
  "what does saliency say", as a `RegionMask`.
- Time this (`AnalysisTimings.saliency`, from LUMO-182) from the start.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §1, §4 — saliency's role.
- LUMO-187's dispatch structure; LUMO-184's `RegionMask`/`SemanticMaskKind`.

## 5. Testing

- `Tests/LumoKitTests/SubjectMaskProviderTests.swift` (new): fixture with an obvious visual
  subject (synthetic, generated per `Fixtures.swift` convention) — assert the resulting mask's
  bounds roughly contain the expected area. Failure path returns a typed error, doesn't crash.
