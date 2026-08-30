---
id: LUMO-046
title: Implement zoom, pan, fit, and fill on the editor canvas
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:32.585Z
updated: 2026-08-30T18:30:50.048Z
depends_on:
  - LUMO-045
  - LUMO-013
estimate: 5
order: x4bipx46
board: product
---

## Objective

Provide fluid native canvas navigation independent of render resolution and inspector state.

## Context

Part of **Epic 8 — Image-centric editor experience**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Separate display transform from destructive crop/output transform.
- Support fit, fill, explicit zoom, scroll/pinch zoom, pan, and reset.
- Request appropriate render sizes when zoom changes without thrashing.
- Keep image centered and constrained predictably.

## Acceptance criteria

- [ ] Fit shows the whole image; Fill covers the viewport; neither alters export.
- [ ] Zoom/pan remain responsive while a better render settles.
- [ ] Changing inspector/sidebar geometry preserves a sensible focal point.
- [ ] Extreme and invalid zoom values clamp safely.

## Verification

- Add transform math tests and manual trackpad/mouse checks on portrait/landscape images.

## Out of scope

- Crop/straighten UI unless separately scheduled.
- Pixel-level retouching.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
