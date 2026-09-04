---
id: LUMO-202
title: High-quality mask refinement for local adjustments
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:56.683Z
updated: 2026-09-04T14:34:45.295Z
depends_on:
  - LUMO-201
  - LUMO-186
order: zzzzzzv
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/MaskRefinement.swift`
**Depends on:** LUMO-201, LUMO-186
**Epic:** LUMO-181 — see mask-quality rationale in `docs/PHASE3_SPEC.md` / LUMO-184

## 1. Problem

Auto only ever needs a `.analysis`-quality mask (~768px); the Masking UI (LUMO-201) shows
`.preview`-quality masks for selection. Neither is precise enough for a local adjustment painted
and rendered at full resolution — that needs `.render`-quality: full-resolution, likely tile-based
to stay within the memory budget (`docs/PHASE3_SPEC.md` §6), refined mattes. This ticket builds
that upgrade path, reusing the semantic detection result as *reusable source data* rather than
re-running Vision from scratch at full resolution.

## 2. Requirement (acceptance criteria)

1. A refinement pipeline that, given an existing lower-quality `RegionMask` (e.g. `.preview`) and
   the full-resolution source image, produces a `.render`-quality `RegionMask` — via a tile-based
   approach that stays within the memory budget rather than processing the whole full-res image at
   once.
2. Reuses the semantic detection already performed (e.g. the approximate subject/person boundary
   from the lower-quality mask) as a guide/seed for refinement, rather than re-running the full
   Vision pipeline blind at full resolution — this is the concrete realization of "Select Subject
   isn't new ML work later, it's exposing what Lumo already computed," from the architecture
   proposal.
3. Uses `MaskOperations.refine(_:)`'s basic hook (LUMO-186) as a starting point if useful, or
   supersedes it with the real tile-based implementation — reconcile the two in whichever ticket
   lands second.
4. Result written through `MaskStore` (LUMO-185) at `.render` quality, keyed consistently.
5. Cancellable and off the main actor — full-res refinement is exactly the kind of work that must
   never block the UI.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- This is explicitly scoped as the mask-quality upgrade pipeline only — the paint/brush editing
  UI that would consume `.render`-quality masks for actual local adjustments is a separate,
  larger effort not covered by this ticket (see LUMO-201's notes).
- Tile-based processing should reuse whatever Core Image tiling/scale infrastructure
  `RenderPipeline`/`RenderEngine` already has for large-image handling, rather than inventing a
  new one.

## 4. Where to look

- LUMO-184's `MaskQuality` — the ordering this ticket upgrades along.
- LUMO-185's `MaskStore`, LUMO-186's `MaskOperations`.
- `Sources/LumoKit/Models/RenderPipeline.swift` — existing large-image/tiling precedent to check
  before inventing a new one.

## 5. Testing

- `Tests/LumoKitTests/MaskRefinementTests.swift` (new): given a synthetic lower-quality mask +
  full-res fixture, assert the refined `.render`-quality mask has higher effective resolution and
  reasonable boundary agreement with the source mask (e.g. IoU above a threshold). Cancellation
  mid-refinement doesn't corrupt `MaskStore`. Memory: rough check that tile-based processing
  doesn't materialize the whole full-res buffer at once (e.g. assert peak memory scales with tile
  size, not full-image size, on a large fixture).
