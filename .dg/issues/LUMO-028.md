---
id: LUMO-028
title: Ship the Light inspector with reset and interaction semantics
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:light
  - phase:4
created: 2026-08-30T18:30:26.475Z
updated: 2026-08-30T18:30:44.328Z
depends_on:
  - LUMO-025
  - LUMO-026
  - LUMO-027
  - LUMO-013
  - LUMO-009
estimate: 5
order: k5rcyk5o
board: product
---

## Objective

Present the complete Light toolset in a collapsible, responsive inspector without leaking CIFilter concepts.

## Context

Part of **Epic 4 — Photographic Light controls**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Use photographer-facing labels/readouts and the specified ranges.
- Support double-click label/value reset, per-control reset, reset Light, and reset photo handoff.
- Group slider gestures for undo and interactive/settled rendering.
- Provide a usable tone-curve editor with keyboard/accessibility support.

## Acceptance criteria

- [ ] All Light controls are reachable without modal UI.
- [ ] Resets affect exactly the intended scope and are undoable.
- [ ] Dragging remains responsive while rendering and produces one undo step.
- [ ] The inspector remains interactive during render cancellation/settling.

## Verification

- Add control model/reset/gesture tests and perform accessibility/keyboard smoke testing.

## Out of scope

- Pixel-local adjustment brushes.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
