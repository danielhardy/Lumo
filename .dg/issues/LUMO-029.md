---
id: LUMO-029
title: Epic 5 — White balance, mixer, and color grading
type: feature
status: backlog
priority: high
labels:
  - mvp
  - epic
  - epic:color
  - phase:5
created: 2026-08-30T18:30:26.827Z
updated: 2026-08-30T18:31:55.187Z
depends_on:
  - LUMO-030
  - LUMO-031
  - LUMO-032
  - LUMO-033
  - LUMO-034
order: kvoha2vl
board: product
---

## Objective

Deliver RAW-aware white balance plus global Color, eight-channel HSL mixer, and three-way color grading with high-quality GPU rendering.

## MVP outcome

- [ ] As Shot, temperature/tint, vibrance/saturation, mixer, and grading persist and render at every quality.
- [ ] Skin, foliage, saturated primaries, and gradients behave predictably.
- [ ] No interactive stage uses Swift CPU pixel loops.

## Child tickets

- LUMO-030 — Implement As Shot and RAW-aware white balance behavior
- LUMO-031 — Harden Vibrance and Saturation as distinct global color controls
- LUMO-032 — Implement the eight-channel HSL Color Mixer
- LUMO-033 — Implement three-way Color Grading with blending and balance
- LUMO-034 — Ship responsive Color, Mixer, and Grading inspector sections

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
