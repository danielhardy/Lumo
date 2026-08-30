---
id: LUMO-032
title: Implement the eight-channel HSL Color Mixer
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:color
  - phase:5
created: 2026-08-30T18:30:27.784Z
updated: 2026-08-30T18:30:45.111Z
depends_on:
  - LUMO-024
estimate: 8
order: n1fu8n1c
board: product
---

## Objective

Add Hue, Saturation, and Luminance controls for Red, Orange, Yellow, Green, Aqua, Blue, Purple, and Magenta.

## Context

Part of **Epic 5 — White balance, mixer, and color grading**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define Codable fixed-channel model and ranges.
- Implement hue-weighted GPU kernel/filter with smooth overlaps and hue wraparound.
- Avoid seams, hard channel boundaries, and CPU loops.
- Include state in hashing, undo, copy/paste, and persistence.

## Acceptance criteria

- [ ] Each channel primarily affects its intended hue neighborhood with smooth falloff.
- [ ] Hue wraparound at red is continuous.
- [ ] Neutral mixer is identity and results are deterministic.
- [ ] Interactive performance meets the common-control target on representative hardware.

## Verification

- Add hue-wheel locality, wraparound, neutral, determinism, and preview/export tests.

## Out of scope

- Targeted adjustment eyedropper.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
