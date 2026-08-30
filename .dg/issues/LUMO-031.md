---
id: LUMO-031
title: Harden Vibrance and Saturation as distinct global color controls
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:color
  - phase:5
created: 2026-08-30T18:30:27.428Z
updated: 2026-08-30T18:30:44.926Z
depends_on:
  - LUMO-024
estimate: 3
order: mbipx4bf
board: product
---

## Objective

Ensure saturation and vibrance have photographer-useful, distinct behavior and correct -100/0/+100 mapping.

## Context

Part of **Epic 5 — White balance, mixer, and color grading**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Map UI values to stable normalized engine values.
- Keep saturation neutral exact and -100 near monochrome.
- Verify vibrance protects already-saturated colors/skin better than uniform saturation.
- Preserve color space and alpha.

## Acceptance criteria

- [ ] Saturation -100 is near-monochrome within tolerance.
- [ ] Vibrance and saturation produce measurably distinct changes on mixed-chroma input.
- [ ] Neutral values are no-ops and preview/export agree.
- [ ] Outputs remain finite and gamut handling is documented.

## Verification

- Add synthetic swatch and representative skin/foliage property tests.

## Out of scope

- Selective masking.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
