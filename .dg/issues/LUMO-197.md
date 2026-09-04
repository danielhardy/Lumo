---
id: LUMO-197
title: Primary subject ensemble scoring
type: feature
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:54.584Z
updated: 2026-09-04T14:34:43.753Z
depends_on:
  - LUMO-194
order: zzzzzx
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/PrimarySubjectSelector.swift`
**Depends on:** LUMO-194
**Epic:** LUMO-181 — see original proposal §18

## 1. Problem

Given `PhotoAnalysis.regions` (LUMO-194), decide which one (or combination) is "the" primary
subject — without hardcoding "subject = foreground instance #1", which breaks for multi-subject
photos (a couple, a person + dog, two children).

## 2. Requirement (acceptance criteria)

1. A scoring function combining signals already present on each `AnalyzedRegion`: attention
   overlap (from the `.subject`/saliency region), foreground confidence, face presence, person
   presence, composition weight (e.g. rule-of-thirds proximity), relative size — each a named,
   documented weight constant.
2. Output: primary subject as a reference/ID into `PhotoAnalysis.regions`, plus `confidence:
   Float`, and optionally a ranked list of secondary subjects.
3. Every decision carries a `confidence` — feeds LUMO-200's conservative-when-uncertain behavior.
4. Zero-subject case (no faces, no foreground, weak/no saliency) returns nil/very-low-confidence,
   not an arbitrary forced pick.
5. Pure function over `[AnalyzedRegion]` — no Vision, no actors, fully unit-testable without
   async.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Continuous scoring (weighted sum → normalized), not nested if/else thresholds — avoid step-
  function instability where near-identical images flip the pick.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §3, original proposal §18.
- LUMO-194's `PhotoAnalysis.regions` — the only input.

## 5. Testing

- `Tests/LumoKitTests/PrimarySubjectSelectorTests.swift` (new): single dominant region → high
  confidence, correct pick. Multiple similar-weight candidates → deterministic pick (order-
  independent), lower confidence. No candidates → nil/very-low-confidence. Repeated runs on
  near-identical inputs → stable pick.
