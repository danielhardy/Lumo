---
id: LUMO-199
title: Scene characteristics (backlighting / high-key / low-key)
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:55.442Z
updated: 2026-09-04T14:34:44.344Z
depends_on:
  - LUMO-198
order: zzzzzz
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/SceneCharacteristicsAnalyzer.swift`
**Depends on:** LUMO-198
**Epic:** LUMO-181 — see original proposal §21–23

## 1. Problem

Naive histogram normalization destroys artistic photographs. Auto needs to distinguish "dark
photograph" (intentional low-key) from "underexposed subject," and detect backlighting so it can
protect background highlights while opening subject shadows. This is the highest-value inference
in the whole subsystem and what makes LUMO-200's Auto Light meaningfully better than today's
global-histogram-only Auto.

## 2. Requirement (acceptance criteria)

1. Populate `SceneCharacteristics` — `hasFaces`, `hasPeople`, `subjectProminence`,
   `subjectBackgroundSeparation`, `tonalKey: TonalKey (low/mid/high)`, `dynamicRange`,
   `backlightingLikelihood`, `highKeyLikelihood`, `lowKeyLikelihood` — from `RegionRelationships`
   (LUMO-198) and `globalTone` (LUMO-192).
2. `backlightingLikelihood`: subject darker than background AND background near upper luminance
   range AND subject occupies meaningful area AND face/foreground confidence (original proposal
   §22) — document the exact formula/thresholds as named constants.
3. `highKeyLikelihood`/`lowKeyLikelihood`: per original proposal §23 — high-key is luminance
   concentrated high with little clipping and a relatively high subject; low-key is majority-dark
   with an intentionally separated subject and small highlight regions.
4. All three scores continuous (`Float` in `0...1`), not booleans — no step-function thresholds.
5. Pure function, no Vision, no actors.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Ship a documented, reasonable-but-tunable formula with named constants — LUMO-207 (Auto tuning)
  exists specifically to refine these against the fixture corpus once it's in place.

## 4. Where to look

- Original proposal §21–23.
- LUMO-198's `RegionRelationships` — primary input.

## 5. Testing

- `Tests/LumoKitTests/SceneCharacteristicsAnalyzerTests.swift` (new): synthetic `PhotoAnalysis`
  fixtures for normal daylight, clear backlit, intentional high-key, intentional low-key — assert
  the corresponding likelihood is clearly dominant for each (semantic assertions, not exact-float
  equality, per `docs/PHASE3_SPEC.md` §7).
