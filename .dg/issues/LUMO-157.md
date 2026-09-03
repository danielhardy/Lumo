---
id: LUMO-157
title: Double-click canvas to toggle between Fit and the last chosen zoom
type: feature
status: ready
priority: medium
labels:
  - canvas
  - zoom
  - ux
  - interaction
  - verification
created: 2026-09-03T14:43:49.871Z
updated: 2026-09-03T14:55:07.646Z
order: n
board: product
---

## Objective

Make double-clicking the image a quick two-way zoom toggle: from Fit, return to
the last manually chosen zoom level; from any zoomed state, return to Fit.

## Context

The canvas already supports Fit, Fill, explicit zoom menu values, panning, and
pinch magnification, but the image has no fast way to alternate between a full-image
view and a previously selected detail level. Users should be able to inspect detail
and then quickly restore the whole composition without reopening the zoom menu.

Relevant current interaction/state code is in
`Sources/LumoKit/Views/PreviewView.swift`,
`Sources/LumoKit/Models/CanvasNavigation.swift`, and the canvas-navigation methods
in `Sources/LumoKit/ViewModels/AppViewModel.swift`.

## Acceptance criteria

- [ ] When the canvas is in Fit mode, double-clicking the image switches to the last
      valid user-chosen zoom level and presents the image without recreating the
      source or changing the edit document.
- [ ] When the canvas is in a custom zoom, Fill, or other non-Fit view, double-clicking
      the image switches to Fit and shows the complete image centered in the viewport.
- [ ] The last chosen zoom level is retained while toggling Fit and remains available
      after repeated Fit/detail double-clicks; it is updated when the user chooses a
      new explicit or gesture-based zoom.
- [ ] Define and test a deterministic fallback when no prior custom zoom exists, and
      ensure invalid, unavailable, or out-of-range remembered values are clamped safely.
- [ ] Double-click handling does not interfere with existing pan, pinch zoom, crop
      interaction, comparison/original-preview behavior, or normal single-click input.
- [ ] Add automated state-transition coverage for Fit → remembered zoom → Fit,
      including Fill and repeated-toggle cases, plus interaction/layout coverage for
      the image surface where practical.

## Implementation notes

Keep zoom/navigation presentation-only and out of `EditDocument` and edit history.
The remembered level may belong in `CanvasNavigation` or its interaction-state owner,
but Fit should not erase it. Choose the smallest gesture API that works with the
existing SwiftUI/AppKit canvas input and preserve the current focal-point/pan policy;
double-clicking need not add a new edit or persistence behavior.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
