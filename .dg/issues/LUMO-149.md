---
id: LUMO-149
title: Add a deterministic one-click Auto photo adjustment
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - mvp
  - ux
  - light
  - color
  - photo-adjustments
created: 2026-09-03T01:12:26.779Z
updated: 2026-09-03T01:26:36.000Z
depends_on:
  - LUMO-028
  - LUMO-034
  - LUMO-048
estimate: 8
order: zzy
board: product
---

## Objective

Provide a clearly labeled Auto action that applies a deterministic, non-destructive baseline of global photo adjustments supported by Lumo's current edit model.

## Context

The concept allows Auto only if technically practical. A first Lumo version should be predictable, reversible, and grounded in `EditDocument`'s existing global Light/Color controls rather than trying to solve every photographic style or imitate another product. “Auto” is the product label; “Magic” is not required.

## Acceptance criteria

- [ ] A clearly labeled Auto action is available when a supported photo is loaded and is disabled or explained when analysis cannot run.
- [ ] One activation computes documented image statistics and writes a baseline only through the existing non-destructive `EditDocument` Light/Color model.
- [ ] The action exposes a visible in-progress state, handles unsupported/failed analysis, and never leaves the canvas or Info histogram in a stuck loading state.
- [ ] Auto is one undoable edit-history operation and does not silently destroy prior manual edits; replace, layer, or reset behavior is explicit in the UX.
- [ ] Repeating Auto is deterministic for the same analyzed input and settings, or is explicitly labeled as a fresh analysis; manual editing remains available afterward.
- [ ] Guardrails for exposure, contrast, highlights, shadows, whites/blacks, and color balance prevent obviously clipped or extreme output and respect each control's existing range.
- [ ] A representative non-redistributable fixture set and lightweight quality rubric evaluate stability and bounds without claiming subjective “good” for every image.
- [ ] Automated coverage verifies the action, document/history behavior, loading/error states, determinism, and representative output bounds.

## Implementation notes

Scope v1 to global adjustments supported by the current renderer. Start with image statistics available from the displayed/source render, document the heuristic and known limitations, and leave style-specific Looks/LUTs and RAW-camera profiling separate.

## Verification

Run deterministic unit tests against representative non-redistributable fixtures, including neutral, clipped, low-key, high-contrast, and color-biased inputs. Verify one-step undo, failure recovery, output bounds, and no histogram/preview loading leak before the full test suite.

## Out of scope

- ML/LLM image understanding, semantic masking, face/sky selection, camera-profile matching, or style transfer.
- Automatic crop, local adjustments, batch Auto, or changes to the renderer's supported control ranges.
