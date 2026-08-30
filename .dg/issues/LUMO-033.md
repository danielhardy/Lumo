---
id: LUMO-033
title: Implement three-way Color Grading with blending and balance
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:color
  - phase:5
created: 2026-08-30T18:30:28.143Z
updated: 2026-08-30T18:30:45.284Z
depends_on:
  - LUMO-024
estimate: 8
order: nrcyk5r9
board: product
---

## Objective

Add shadows, midtones, and highlights hue/saturation wheels plus Blending and Balance.

## Context

Part of **Epic 5 — White balance, mixer, and color grading**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define compact Codable model with neutral semantics.
- Implement luminance-weighted GPU application with smooth tonal overlap.
- Make balance shift tonal regions and blending control overlap predictably.
- Keep stage order versioned relative to mixer/effects/LUT.

## Acceptance criteria

- [ ] Each wheel predominantly affects its intended tonal region.
- [ ] Blending and Balance have independent, monotonic effects.
- [ ] Zero saturation across all wheels is identity regardless of hue.
- [ ] No visible discontinuity appears on a smooth grayscale gradient.

## Verification

- Add tonal-region, identity, gradient-continuity, and parity tests.

## Out of scope

- Channel curves.
- Local grading masks.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
