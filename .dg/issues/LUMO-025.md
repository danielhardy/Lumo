---
id: LUMO-025
title: Refine Exposure, Contrast, Highlights, and Shadows behavior
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:light
  - phase:4
created: 2026-08-30T18:30:25.335Z
updated: 2026-08-30T18:30:43.039Z
depends_on:
  - LUMO-024
estimate: 5
order: hzzzzzzx
board: product
---

## Objective

Make the inherited controls photographically sensible and distinct using GPU-backed Core Image/Metal operations.

## Context

Part of **Epic 4 — Photographic Light controls**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Keep exposure approximately EV-based.
- Make contrast alter separation without immediate endpoint clipping.
- Localize highlights to upper tones and shadows to lower tones.
- Avoid CPU per-pixel loops.

## Acceptance criteria

- [ ] +1 Exposure measurably approximates one-stop brightening on a linear test ramp.
- [ ] Highlights affect upper luminance more than shadows; Shadows show the inverse.
- [ ] Moderate contrast preserves usable endpoints.
- [ ] Interactive and export results are directionally/perceptually consistent.

## Verification

- Add numeric-region property tests and visual samples for highlight, shadow, and underexposed scenes.

## Out of scope

- Camera-specific Adobe matching.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
