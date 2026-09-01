---
id: LUMO-080
title: Make tone-curve dragging a smooth real-time curve with live image feedback
type: task
status: backlog
priority: high
labels:
  - mvp
  - live-preview
  - light
  - ux
created: 2026-09-01T03:00:52.537Z
updated: 2026-09-01T03:00:52.537Z
order: zzzq
board: product
---

## Objective

Make tone-curve dragging feel like direct manipulation: the visible curve should bend smoothly
under the pointer and the edited image should update continuously while the pointer is down.

## Context

The current `ToneCurveEditor` in `Sources/LumoKit/Views/LightInspectorView.swift` draws the
master RGB transfer function from `LightToneCurve.value(at:)`, which is piecewise-linear between
control points. Dragging an interior handle can therefore read as moving a single pivot/kink: the
control point moves, but the UI does not communicate a smooth curve being shaped under the pointer.
The image preview also needs to make each meaningful drag position visible before mouse-up; a
curve edit that only becomes apparent after the gesture is over feels disconnected from both the
graph and the photograph.

This ticket covers the interaction and presentation behavior on top of the existing live-preview
rendering path. Preview and export must continue to consume the same persisted `LightToneCurve`
values so the on-screen result remains authoritative.

## Acceptance criteria

- [ ] Pressing and dragging an interior tone-curve handle updates the handle position and the
  rendered curve continuously on every pointer movement; the line visibly follows the pointer
  before mouse-up.
- [ ] The edited transfer function is rendered as a smooth, shape-preserving curve with a local
  bend around the dragged region, rather than presenting the interaction as a single pivot or a
  visibly angular pair of straight segments. The interpolation must not overshoot or introduce
  tone inversions when the control points are monotonic.
- [ ] Direct manipulation remains predictable: the dragged point stays under the pointer, adjacent
  tones transition smoothly, endpoints remain fixed, and control-point ordering/invariants remain
  valid throughout the gesture.
- [ ] Each intermediate curve state updates the displayed photograph through the live preview
  path while the drag is in progress. The image visibly changes before mouse-up, with no
  mouse-up-only refresh, blank frame, or stale curve revision presented after a newer drag value.
- [ ] Interactive updates remain frame-paced/latest-wins and do not regress the existing bounded
  tone-curve rendering path or allocate a full-resolution image object for every pointer tick.
- [ ] Releasing the pointer settles the final curve without a visual jump, and the settled preview
  and full-resolution export produce the same tone mapping for the final document.
- [ ] Add regression coverage for curve-path updates during a drag, smooth interpolation around a
  moved point, monotonicity/invariant preservation, intermediate preview publication, and preview /
  export parity. Update accessibility behavior if the interaction model changes.

## Implementation notes

- Prefer a shape-preserving cubic or equivalent smooth interpolation that preserves endpoint and
  control-point values and cannot overshoot monotonic input data. Keep the persisted model
  resolution-independent; do not replace it with a UI-only curve that export cannot reproduce.
- The UI curve and renderer must use one shared interpolation definition (or equivalent sampled
  representation) so the line shown in the graph matches the pixels in the photograph.
- Keep the existing undo coalescing semantics: one continuous drag should remain one undo step.
- Relevant code: `Sources/LumoKit/Views/LightInspectorView.swift`,
  `Sources/LumoKit/Models/LightAdjustments.swift`,
  `Sources/LumoKit/ViewModels/AppViewModel+Light.swift`, and the live preview coordinator/surface.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
