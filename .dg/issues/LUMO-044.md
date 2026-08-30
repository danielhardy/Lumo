---
id: LUMO-044
title: Epic 8 — Image-centric editor experience
type: feature
status: backlog
priority: urgent
labels:
  - mvp
  - epic
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:31.996Z
updated: 2026-08-30T18:31:55.799Z
depends_on:
  - LUMO-045
  - LUMO-046
  - LUMO-047
  - LUMO-048
  - LUMO-049
order: voha2voc
board: product
---

## Objective

Replace the LUT-centric shell with a native grid/edit workflow centered on a large canvas, responsive inspectors, filmstrip, comparison, and keyboard navigation.

## MVP outcome

- [ ] G/E navigation moves cleanly between Library and Edit.
- [ ] Canvas supports fit/fill/zoom/pan and before/after.
- [ ] Inspectors, histogram, filmstrip, focus, and reset behavior remain responsive during rendering.

## Child tickets

- LUMO-045 — Build the Library/Edit navigation shell and image-centric layout
- LUMO-046 — Implement zoom, pan, fit, and fill on the editor canvas
- LUMO-047 — Unify before/after comparison for every edit stage
- LUMO-048 — Coalesce histogram updates from the displayed render
- LUMO-049 — Complete filmstrip navigation, focus-safe shortcuts, resets, and accessibility

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
