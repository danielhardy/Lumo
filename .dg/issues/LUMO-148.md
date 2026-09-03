---
id: LUMO-148
title: Create a tone-curve handle when dragging an empty curve location
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - tone-curve
  - editor
  - interaction
  - accessibility
created: 2026-09-03T01:12:26.210Z
updated: 2026-09-03T01:12:26.495Z
order: zzy
board: product
---

## Objective

Allow a user to create and drag a tone-curve point in one gesture by pressing on an empty curve location and dragging.

## Context

Today, clicking an empty location does not create a handle during the drag. The user must add a point first, then begin a second drag. This makes the core curve interaction feel unnecessarily slow.

## Acceptance criteria

- [ ] Pointer down on an empty, valid curve location creates a handle at that curve coordinate and starts dragging it in the same gesture.
- [ ] The handle follows pointer movement until pointer up, with values clamped to the supported curve bounds.
- [ ] Pressing an existing handle continues to select and drag that handle without creating a duplicate.
- [ ] Click/tap without movement still creates a point once, and canceling/interruption does not leave duplicate or orphaned points.
- [ ] The interaction works for each supported channel/curve mode and preserves undo/redo behavior.
- [ ] Keyboard and assistive-technology users retain an accessible way to add, select, move, and remove points.
- [ ] Automated interaction tests cover empty-location drag, existing-handle drag, bounds, channel modes, cancellation, and undo/redo.

## Implementation notes

Use the same coordinate-to-curve mapping and hit-testing rules as the existing point-add interaction. Ensure pointer capture and state updates are released on pointer cancel, window loss, and touch input.
