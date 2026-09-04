---
id: LUMO-207
title: Auto tuning across corpus
type: task
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:58.939Z
updated: 2026-09-04T14:34:46.902Z
depends_on:
  - LUMO-200
  - LUMO-204
  - LUMO-205
order: zzzzzzzq
board: product
---

**Type:** Task
**Component:** `Sources/LumoKit/Models/PhotoAnalysis/AutoLightEngine.swift` and its evaluators
(tuning only, no new architecture)
**Depends on:** LUMO-200, LUMO-204, LUMO-205
**Epic:** LUMO-181 — see original proposal §41, §44–46

## 1. Problem

`AutoLightEngine` (LUMO-200) and `SceneCharacteristicsAnalyzer` (LUMO-199) ship with reasonable-
but-unvalidated constants. This ticket is the deliberate tuning pass against the fixture corpus
(LUMO-204) using the visual regression harness (LUMO-205).

## 2. Requirement (acceptance criteria)

1. Run the harness against the full corpus and record a baseline report before changes.
2. Adjust named constants in LUMO-199/200 based on the corpus report — every change justified by
   a specific before/after comparison, not intuition alone.
3. Bump `AutoLightEngine`'s algorithm version when tuning changes output meaningfully.
4. Golden-range tests updated to reflect tuned ranges, keeping the "ranges, not exact values"
   discipline.
5. No architectural changes — file a follow-up ticket if tuning reveals a structural problem.
6. Regression report shows net improvement or neutrality — zero regressions without a documented
   reason.
7. `swift test` stays green.

## 3. Implementation notes

- If the corpus is still small at this point (LUMO-204 scopes it to dozens of synthetic fixtures
  pending a licensed real-photo corpus via `LUMO_RAW_FIXTURE_DIR`), note that explicitly as a
  known limitation on how far this tuning pass can be trusted.

## 4. Where to look

- LUMO-200's `AutoLightEngine`, LUMO-199's `SceneCharacteristicsAnalyzer` — what's tuned.
- LUMO-204's corpus, LUMO-205's harness — the tools this ticket runs.

## 5. Testing

- Before/after visual regression report summary attached to the completion comment.
- Updated golden-range tests pass; full `swift test` green.
