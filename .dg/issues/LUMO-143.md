---
id: LUMO-143
title: Fix intermittent black canvas and stuck histogram when switching photo thumbnails
type: bug
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - defect
  - photo-loading
  - thumbnails
  - histogram
created: 2026-09-03T01:12:23.443Z
updated: 2026-09-03T01:12:23.734Z
order: zzy
board: product
---

## Objective

Make thumbnail-based photo switching reliably load the selected image and histogram without requiring a tab change as a workaround.

## Context

Clicking thumbnails sometimes shows a spinner briefly and then resolves to a black/empty canvas. The histogram also fails to load or remains in a loading state. Clicking the Light tab can cause the photo to appear, but returning to the tab leaves the histogram stuck. This suggests a race or stale state between photo selection, image decode/render, histogram calculation, and tab activation.

## Acceptance criteria

- [ ] Every successful thumbnail selection eventually shows the selected photo on the canvas and a completed histogram when histogram data is supported.
- [ ] After loading settles, the UI does not show a spinner or loading histogram indefinitely; decode, unsupported-format, and calculation failures use an actionable error/empty state.
- [ ] Switching thumbnails rapidly resolves to the latest selected photo and does not allow a stale request to overwrite the canvas or histogram.
- [ ] Switching between editing tabs does not trigger the only successful render path and does not regress the loaded photo or histogram state.
- [ ] The behavior works for edited and unedited photos and for repeated selection of the same thumbnail.
- [ ] Automated regression tests cover thumbnail selection, rapid selection changes, loading failure, histogram failure, and tab switching.

## Implementation notes

Trace request cancellation or generation IDs across selection, image decode, canvas render, and histogram computation. Keep one authoritative selected-photo state and ensure every async completion verifies that it still belongs to that selection before committing UI state.
