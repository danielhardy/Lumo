---
id: LUMO-148
title: Create a tone-curve point when dragging an empty curve location
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - light
  - ux
  - live-preview
  - accessibility
  - tone-curve
created: 2026-09-03T01:12:26.210Z
updated: 2026-09-03T01:26:36.000Z
depends_on:
  - LUMO-080
  - LUMO-091
estimate: 3
order: zzy
board: product
---

## Objective

Allow a user to create and drag a master RGB tone-curve point in one gesture by pressing on an empty curve location and dragging.

## Context

The Light inspector's master RGB curve already has model operations for adding, moving, and removing normalized points, and LUMO-080/LUMO-091 established the live-preview interaction path. Today, clicking an empty location does not create a handle during the drag; the user must add a point first, then begin a second drag.

## Acceptance criteria

- [ ] Pointer down on an empty, valid location in the master RGB curve creates one normalized point at the curve coordinate and starts dragging it in the same gesture.
- [ ] The point follows pointer movement until pointer up, with input/output clamped to `0...1` and the endpoint invariants preserved.
- [ ] Pressing an existing point selects and drags it without creating a duplicate; a near-point hit uses the existing hit-testing tolerance.
- [ ] A click/tap without movement creates one point, and pointer cancellation, window loss, or interruption does not leave duplicate/orphaned points.
- [ ] The gesture participates in the existing coalesced preview and one undo/redo grouping for the whole drag.
- [ ] Keyboard and assistive-technology users retain an accessible way to add, select, move, and remove points through the existing curve controls.
- [ ] Automated interaction/model coverage exercises empty-location drag, existing-point drag, bounds, cancellation, duplicate prevention, live preview, and undo/redo.

## Implementation notes

Use the same coordinate-to-curve mapping, interpolation, and hit-testing rules as `LightToneCurve.addingPoint`/the existing point editor. Ensure pointer capture and state updates are released on pointer cancel, window loss, and supported pointer/touch input.

## Verification

Run focused tone-curve interaction/model tests and the full Swift test suite. Manually verify pointer drag, click-without-movement, cancellation, existing-point hit testing, keyboard access, and VoiceOver labels.

## Out of scope

- Adding separate per-channel curves or changing the persisted tone-curve schema.
- Replacing the live-preview surface or changing unrelated Light controls.
