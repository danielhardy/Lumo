---
id: LUMO-189
title: Face detection + face mask provider
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:51.306Z
updated: 2026-09-04T14:34:41.219Z
depends_on:
  - LUMO-187
  - LUMO-185
order: zzzzq
board: product
---

**Type:** Feature
**Component:** `Sources/LumoKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift` (+`.face`
mask + face detection)
**Depends on:** LUMO-187, LUMO-185
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §4 (Tier 3), original proposal §19

## 1. Problem

Faces matter disproportionately for perceived exposure quality, and a user will want to select
"Face" directly in the Masking UI (LUMO-201) — both consume the exact same `.face` `RegionMask`
this ticket produces. This is face **detection**/masking only — not landmarks, not identity, not
demographics, and explicitly not a "target skin brightness" heuristic.

## 2. Requirement (acceptance criteria)

1. Implement `VisionSemanticMaskProvider.mask(for: .face, image:, quality:)` using Vision face
   detection. At `.analysis`/`.preview` a bounding-rect-derived mask is acceptable; document
   whether `.render` quality warrants landmark-based refinement or stays rect-derived (a rect-
   derived face mask is a reasonable v1 — don't add landmark parsing unless a concrete `.render`
   consumer needs it).
2. Small/background faces (below a documented minimum coverage) are still detected but their
   `RegionMask.confidence`/`coverage` reflect that, so downstream consumers (LUMO-197's ensemble
   scoring) can discount them rather than treating every face as equally important.
3. **Hard constraint:** no "correct" skin brightness value or target anywhere in this code —
   detection/masking only. Relational judgments belong to LUMO-198 (`RegionRelationships`).
4. Multiple faces produce multiple `RegionMask`s (one `.face` mask per detected face — decide and
   document how multiple faces are addressed, e.g. via a face index alongside `.face`, similar to
   `.foregroundInstance(Int)`'s pattern in LUMO-184; if `SemanticMaskKind.face` needs an associated
   index for multi-face photos, add it here and update LUMO-184's enum in the same PR).
5. Failure/unsupported throws a typed, catchable error.
6. Coordinates via LUMO-183; Vision revision recorded in `VisionConfiguration`.
7. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- If you need to change `SemanticMaskKind` (§2.4 above), that's a legitimate, expected outcome of
  this ticket — LUMO-184 shipped with a best-guess enum, and this is exactly the kind of shape
  question that's cheaper to resolve once a real multi-instance case (faces, like foreground
  objects) is implemented than to have guessed correctly up front.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §4, §19 rationale.
- LUMO-184's `SemanticMaskKind.foregroundInstance(Int)` — the existing pattern for multi-instance
  kinds, reusable for faces.

## 5. Testing

- `Tests/LumoKitTests/FaceMaskProviderTests.swift` (new): per CLAUDE.md's "fixtures are
  generated, never committed" rule, prefer a synthetic face-like pattern if Vision's detector
  reliably fires on one (verify empirically); otherwise gate positive-detection assertions behind
  `LUMO_RAW_FIXTURE_DIR` like the opt-in slow RAW lane, keeping the no-face/empty-result and
  failure-path cases always-on. Multi-face fixture (if available) — assert one `RegionMask` per
  face.
