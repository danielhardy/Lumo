---
id: LUMO-017
title: Epic 3 — Folder library and rapid culling
type: feature
status: done
priority: urgent
labels:
  - mvp
  - epic
  - epic:library
  - phase:3
created: 2026-08-30T18:30:22.834Z
updated: 2026-08-31T18:34:58.679Z
depends_on:
  - LUMO-018
  - LUMO-019
  - LUMO-020
  - LUMO-021
  - LUMO-022
order: a0
board: product
commits:
  - HEAD
---

## Objective

Turn the inherited folder/filmstrip support into a scalable grid-first library for hundreds or thousands of photos.

## MVP outcome

- [ ] Folders populate progressively with stable assets and thumbnails.
- [ ] Selection, pick/reject, ratings, filters, and keyboard culling are immediate and persistent.
- [ ] Large folders remain responsive and security-scoped access survives relaunch.

## Child tickets

- LUMO-018 — Introduce stable PhotoAsset and library metadata records
- LUMO-019 — Build progressive cancellable folder ingestion and metadata loading
- LUMO-020 — Create a prioritized thumbnail service using embedded previews when useful
- LUMO-021 — Build a virtualized library grid with multi-selection
- LUMO-022 — Implement rating, pick/reject, filters, and keyboard culling

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T18:34:58.677Z: Verified Epic 3 on merged main: stable PhotoAsset identity and source fingerprints, progressive cancellable folder ingestion with deferred metadata, prioritized embedded-preview thumbnails, lazy virtualized grid admission, multi-selection, keyboard culling, composable filters, undo, persistent culling state, and security-scoped folder restoration. Full verification passed: swift test (353 passed, 20 skipped), swift build -c release, dg validate, and git diff --check.
