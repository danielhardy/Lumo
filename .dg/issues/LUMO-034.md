---
id: LUMO-034
title: Ship responsive Color, Mixer, and Grading inspector sections
type: task
status: done
priority: medium
labels:
  - mvp
  - epic:color
  - phase:5
created: 2026-08-30T18:30:28.536Z
updated: 2026-08-31T21:08:30.752Z
depends_on:
  - LUMO-030
  - LUMO-031
  - LUMO-032
  - LUMO-033
  - LUMO-013
  - LUMO-009
estimate: 5
order: y
board: product
commits:
  - 3ceeedc
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

### Comment — codex @ 2026-08-31T21:08:30.561Z

Implemented commit 3ceeedc: added the complete Color inspector surface in the existing Adjust tab with White Balance, global Color, eight-channel Color Mixer/HSL, and three-way Color Grading disclosure sections. Added numeric entry, per-control/channel/wheel/section resets, contextual accessibility labels, RAW-aware white balance routing, and interactive/debounced preview bindings. Added six focused mapping/reset/interaction tests. Verification: swift test (418 executed, 21 expected skips), swift build -c release, git diff --check, and dg validate passed; validate retains only pre-existing runner-model and LUMO-029 context warnings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T21:08:30.750Z: Shipped responsive Color, Mixer, and Grading inspector sections with RAW-aware white balance, precise numeric entry, scoped resets, accessibility context, and coalesced interactive rendering. Added focused mapping/reset/gesture tests. Verified with swift test (418 passed, 21 expected skips), release build, git diff --check, and dg validate.
