---
id: LUMO-191
title: Person segmentation mask provider
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:52.110Z
updated: 2026-09-04T14:34:41.882Z
depends_on:
  - LUMO-189
  - LUMO-190
order: zzzzx
board: product
---

**Type:** Feature
**Component:** `Sources/LumoKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift` (+`.person`)
**Depends on:** LUMO-189, LUMO-190
**Epic:** LUMO-181 — see original proposal §8, §19

## 1. Problem — note the sequencing change

An earlier draft of this plan treated person segmentation as a late "refinement" ticket, gated
behind Auto shipping. That was wrong: since masks are now shared infrastructure consumed by both
Auto *and* the Masking UI (LUMO-201) from day one, `.person` needs to exist as a core mask kind
alongside face/foreground — the Masking UI's "Person" option depends on it directly, not on
anything Auto-specific. What *does* stay a later, separate ticket is upgrading person mattes to
full-resolution `.render` quality for local-adjustment painting (LUMO-202) — this ticket only
needs to work at `.analysis`/`.preview` quality.

## 2. Requirement (acceptance criteria)

1. Implement `mask(for: .person, image:, quality:)` using Vision's person segmentation request,
   selecting a Vision-side quality level appropriate to the requested `MaskQuality` (e.g. Vision's
   own fast/balanced setting for `.analysis`/`.preview` — full/accurate reserved for `.render`,
   which this ticket doesn't need to satisfy yet; document what happens if `.render` is requested
   here before LUMO-202 lands — a clean "not yet supported at this quality" error is fine).
2. **Demand-driven gating**: only compute a person matte when a `.face` mask (LUMO-189) or a
   plausible person-shaped `.foregroundInstance` (LUMO-190) was already found for this image —
   don't run person segmentation on a landscape with no people. This gating can live in this
   ticket's implementation of `mask(for: .person, ...)` itself (check for an existing face/
   foreground result before doing the Vision call) or in the coordinator (LUMO-195) — pick
   whichever is cleaner and document the choice.
3. Result written through `MaskStore`, keyed consistently.
4. Failure/unsupported/gated-out throws or returns a typed, catchable "not applicable" result —
   not a crash.
5. Coordinates via LUMO-183; Vision revision recorded in `VisionConfiguration`.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Keep this additive: existing behavior for non-people images must be unaffected by this ticket
  landing (the gating in §2.2 is what guarantees that).

## 4. Where to look

- Original proposal §8, §19.
- LUMO-189 (faces), LUMO-190 (foreground) — the two signals that gate whether this runs.

## 5. Testing

- `Tests/LumoKitTests/PersonMaskProviderTests.swift` (new): fixture with a clear person-shaped
  foreground + face → person matte produced. Fixture with no face/person-shaped foreground →
  person segmentation is skipped entirely (assert the Vision request was never issued, via a call
  counter on a fake/spy). Failure path.
