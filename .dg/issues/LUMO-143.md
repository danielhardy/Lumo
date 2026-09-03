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
  - bug
  - regression
  - navigation
  - photo-loading
  - rendering
  - histogram
created: 2026-09-03T01:12:23.443Z
updated: 2026-09-03T01:26:36.000Z
depends_on:
  - LUMO-048
  - LUMO-109
  - LUMO-130
estimate: 5
order: zzy
board: product
---

## Objective

Make filmstrip/library-thumbnail photo switching reliably load the selected image and histogram without requiring an inspector-tab change as a workaround.

## Context

The filmstrip and Library grid both hand off through the same `AppViewModel` source-selection path. A thumbnail click can currently leave a spinner, black/empty presentation, or a histogram that never settles; visiting the Light tab can accidentally trigger the missing render. This indicates stale or competing revisions between selection, `RenderEngine` source preparation, preview presentation, histogram work, and `InspectorState` tab activation. LUMO-142 covers the narrower identity-document comparison bug; this ticket covers request ordering and lifecycle across thumbnail switches.

## Acceptance criteria

- [ ] Every successful thumbnail selection eventually presents that photo on the canvas and settles the Info histogram when the source supports histogram data.
- [ ] Once loading settles, no spinner or loading histogram remains indefinitely; decode, unsupported-format, and calculation failures use an actionable error or explicit empty state.
- [ ] Rapid thumbnail changes resolve to the latest selected `PhotoAssetID`; stale source, preview, metadata, or histogram completions cannot overwrite it.
- [ ] Switching inspector tabs is not required to complete rendering and does not reset the loaded photo, preview, or histogram state.
- [ ] The behavior works for edited and unedited photos, repeated selection of the same thumbnail, and both the filmstrip and Library grid entry points.
- [ ] Automated regression coverage exercises normal, rapid, repeated, failed-source, failed-histogram, and tab-switching paths with explicit revision/ownership assertions.

## Implementation notes

Trace cancellation and the existing source/display/document revision IDs across `ImageCollection`, source preparation, preview presentation, metadata, and histogram computation. Keep `collection.selection.activeID`/the active source as the authority and require every async completion to prove ownership before publishing UI state. Preserve the existing last-presented valid frame behavior for failures.

## Verification

Run focused navigation, preview, and histogram tests plus the full Swift test suite. Record a manual rapid-thumbnail pass covering both filmstrip and Library grid, tab switching, repeated selection, edited/unedited sources, and a representative decode failure.

## Out of scope

- Changing the comparison-mode semantics or redesigning the histogram visualization.
- Adding a new thumbnail service or broad cache rewrite beyond the smallest ownership/cancellation fix.
