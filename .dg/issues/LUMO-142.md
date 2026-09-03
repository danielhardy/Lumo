---
id: LUMO-142
title: Fix black comparison surface when a new unedited photo loads
type: bug
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - bug
  - comparison
  - rendering
  - regression
created: 2026-09-03T01:12:22.879Z
updated: 2026-09-03T01:12:23.162Z
depends_on:
  - LUMO-099
  - LUMO-109
estimate: 3
order: zzy
board: product
---

## Objective

Ensure both sides of Lumo's side-by-side comparison render when the last-used comparison mode is retained and a newly loaded photo has no visible edits.

## Context

Lumo calls this mode “Side by Side” and persists the single-versus-comparison preference independently of the active photo. When that preference survives a photo switch, an identity `EditDocument` still has valid source pixels; the current and comparison panes must both use the settled source/render path rather than treating the lack of visible edits as a missing comparison image. This ticket covers the settled unedited-source case, not the broader thumbnail-switch race tracked separately in LUMO-143.

## Acceptance criteria

- [ ] With the comparison preference enabled, switching to a photo with no saved edits settles with both the source/comparison and current/edited surfaces showing valid pixels; neither surface is black or empty.
- [ ] The result is the same for no edit record, an empty persisted `EditDocument`, and a newly created default document.
- [ ] A transient loading state is allowed, but a settled decode/render failure uses Lumo's existing actionable error state and never masquerades as a black comparison pane.
- [ ] Photos with edits continue to compare correctly, including Reset Photo, Space-hold original, and switching back to single view.
- [ ] Regression coverage asserts the source/render requests and settled presentation state for unedited images while preserving the existing comparison preference across source changes.

## Implementation notes

Audit initialization of the comparison/current render surfaces and their revision gates when `AppViewModel.load` installs a new `ImageSource`. Avoid treating an identity document as “no render output”; the current pane should use the source-derived render until an edit pipeline produces a different result.

## Out of scope

- Reworking comparison-mode UI or changing the user's persisted single/side-by-side preference.
- Fixing rapid thumbnail-selection races or histogram scheduling; those belong to LUMO-143.
