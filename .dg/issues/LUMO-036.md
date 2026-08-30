---
id: LUMO-036
title: Implement distinct Texture, Clarity, and Dehaze stages
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:effects
  - phase:6
created: 2026-08-30T18:30:29.106Z
updated: 2026-08-30T18:30:46.603Z
depends_on:
  - LUMO-024
estimate: 8
order: px4bipx0
board: product
---

## Objective

Create three photographically useful GPU-backed operations rather than variants of one contrast slider.

## Context

Part of **Epic 6 — Photographic effects**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Texture targets medium/high-frequency detail with limited tone shift.
- Clarity targets local midtone contrast.
- Dehaze combines local contrast/tone/color behavior for haze perception.
- Normalize scale-sensitive radii across preview and export.

## Acceptance criteria

- [ ] Frequency/tone tests distinguish all three controls.
- [ ] Neutral is identity and negative values produce sensible inverse effects.
- [ ] No halos or clipping become objectionable at moderate settings on validation images.
- [ ] Interactive implementation contains no per-pixel Swift loop.

## Verification

- Add frequency-pattern, tonal-region, extent, parity, and visual quality tests.

## Out of scope

- AI atmospheric correction.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
