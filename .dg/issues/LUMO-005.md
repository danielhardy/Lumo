---
id: LUMO-005
title: Epic 1 — Durable per-photo edit domain
type: feature
status: backlog
priority: urgent
labels:
  - mvp
  - epic
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:18.651Z
updated: 2026-08-30T18:31:54.455Z
depends_on:
  - LUMO-006
  - LUMO-007
  - LUMO-008
  - LUMO-009
  - LUMO-010
order: 3lllllll
board: product
---

## Objective

Make every source photo own a small, versioned, persistent nondestructive edit record that supports navigation, undo, and edit transfer.

## MVP outcome

- [ ] Edits are isolated per stable photo identity and survive relaunch.
- [ ] Undo/redo groups continuous gestures correctly.
- [ ] Copy/paste can apply edits to one or many selected photos without touching originals.

## Child tickets

- LUMO-006 — Version the durable edit schema and rendering pipeline identity
- LUMO-007 — Isolate edit state per photo during navigation
- LUMO-008 — Persist per-photo edit records with atomic recovery
- LUMO-009 — Implement per-photo undo and redo with gesture grouping
- LUMO-010 — Copy and paste edits to one or many photos

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
