---
id: LUMO-034
title: Ship responsive Color, Mixer, and Grading inspector sections
type: task
status: backlog
priority: medium
labels:
  - mvp
  - epic:color
  - phase:5
created: 2026-08-30T18:30:28.536Z
updated: 2026-08-30T18:30:46.422Z
depends_on:
  - LUMO-030
  - LUMO-031
  - LUMO-032
  - LUMO-033
  - LUMO-013
  - LUMO-009
estimate: 5
order: oha2voh6
board: product
---

## Objective

Expose the complete color model through collapsible native controls optimized for precise editing.

## Context

Part of **Epic 5 — White balance, mixer, and color grading**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Add White Balance, Color, Mixer, and Grading sections.
- Provide per-row/section resets and numeric entry where valuable.
- Group gestures for undo and interactive render coalescing.
- Keep long mixer/grading panels navigable and accessible.

## Acceptance criteria

- [ ] Every MVP color parameter is editable and resettable.
- [ ] UI values round-trip without drift through model mappings.
- [ ] Controls remain responsive while expensive kernels render.
- [ ] Keyboard focus and accessibility labels make repeated channels distinguishable.

## Verification

- Add mapping/reset tests and manual keyboard/VoiceOver smoke tests.

## Out of scope

- Selective copy UI.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
