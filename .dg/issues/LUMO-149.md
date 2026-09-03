---
id: LUMO-149
title: Add one-click Auto/Magic photo adjustment
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto-edit
  - smart-editing
  - photo-adjustments
created: 2026-09-03T01:12:26.779Z
updated: 2026-09-03T01:12:27.059Z
order: zzy
board: product
---

## Objective

Provide a one-click Auto/Magic action that applies a sensible, non-destructive baseline of automatic photo adjustments.

## Context

Photomator and Lightroom offer a quick way to get an image looking good without manual tuning. A first version should be predictable, reversible, and grounded in the editor's existing adjustment model rather than trying to solve every photographic style.

## Acceptance criteria

- [ ] A clearly labeled Auto or Magic action is available when a supported photo is loaded.
- [ ] One activation analyzes the image and applies a documented baseline adjustment set using the existing non-destructive edit model.
- [ ] The action has a visible in-progress state, handles unsupported/failed analysis, and never leaves the canvas or histogram in a stuck loading state.
- [ ] Auto can be undone in one step and does not destroy the user's prior manual edits; the UX for replacing, layering, or resetting the current edits is explicit.
- [ ] Repeating Auto is deterministic or clearly documented as a re-analysis, and the user can continue manual editing afterward.
- [ ] The algorithm has guardrails for exposure, contrast, highlights, shadows, white/black point, and color balance so it avoids obviously clipped or extreme results.
- [ ] A representative fixture set and a lightweight quality rubric are added so changes can be evaluated consistently; the rubric does not claim subjective “good” for every image.
- [ ] Automated coverage verifies the action, edit-history behavior, loading/error states, and representative output bounds.

## Implementation notes

Scope v1 to global adjustments supported by the current renderer. Start with image statistics and/or an existing image-analysis library, document the heuristic and known limitations, and leave style-specific looks to Looks/LUTs.
