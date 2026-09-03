---
id: LUMO-088
title: Redesign Color Grading with Resolve-style visual color wheels
type: feature
status: done
priority: high
model: gpt-5.6-terra
labels:
  - mvp
  - ux
  - epic:color
created: 2026-09-01T14:35:34.567Z
updated: 2026-09-01T15:27:37.871Z
order: z
board: product
---

## Objective

Make three-way Color Grading more visual and direct by presenting Shadows, Midtones, and Highlights
as Resolve-inspired color wheels/spheres rather than only rows of sliders.

## Context

The color-grading model already has separate tonal zones plus hue, saturation, luminance, blending,
and balance controls, but `ColorInspectorView` exposes each zone primarily as a disclosure group
of numeric sliders. A visual wheel should make the hue direction and amount legible at a glance and
support direct manipulation while preserving precise entry and the existing render mapping.

## Acceptance criteria

- [ ] Shadows, Midtones, and Highlights each have a clearly labeled visual color wheel/sphere with
  a visible neutral center and an indicator for the current grade.
- [ ] Dragging a wheel maps predictably to the existing zone hue/saturation values and updates the
  preview continuously; neutral and edge values remain reachable.
- [ ] Existing numeric controls remain available for precision, with values round-tripping without
  drift and per-zone reset still working.
- [ ] Visual treatment remains usable at inspector width, supports light/dark appearance, and has
  meaningful VoiceOver labels/adjustable actions.
- [ ] Add mapping, gesture, reset, accessibility, and preview/export-parity regression coverage.

## Implementation notes

Relevant code: `Sources/LumoKit/Views/ColorInspectorView.swift`,
`Models/ColorGradingAdjustments.swift`, `ViewModels/AppViewModel+Color.swift`, and the existing
grading render stage. Reuse the current model and kernel; this is an interaction/presentation
change, not a new grading algorithm.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T15:27:37.869Z: Added Resolve-style Shadows, Midtones, and Highlights wheels with direct polar dragging, neutral/current indicators, numeric round-trip controls, VoiceOver adjustments/reset, and mapping/interaction/parity coverage. swift test: 503 passed (26 fixture-dependent RAW skips).
