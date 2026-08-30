---
id: LUMO-050
title: Epic 9 — Reliable full-resolution export
type: feature
status: backlog
priority: urgent
labels:
  - mvp
  - epic
  - epic:export
  - phase:9
created: 2026-08-30T18:30:34.407Z
updated: 2026-08-30T18:31:55.978Z
depends_on:
  - LUMO-051
  - LUMO-052
  - LUMO-053
order: zn
board: product
---

## Objective

Generalize the inherited export path into current/selected full-resolution output with photographer-facing options, progress, cancellation, and isolated failures.

## MVP outcome

- [ ] JPEG, 16-bit TIFF, retained PNG, and cleanly supported HEIF export from originals plus saved edits.
- [ ] Selected-photo batches report progress, cancel, and isolate failures.
- [ ] Sizing, color, naming, and metadata policy are explicit and tested.

## Child tickets

- LUMO-051 — Define durable export options and format capabilities
- LUMO-052 — Export current or selected photos from originals and saved edits
- LUMO-053 — Add batch progress, cancellation, collision handling, and failure isolation
- LUMO-054 — Add optional Apple Photos delivery after file export is stable (stretch; non-blocking)

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every required child ticket; LUMO-054 is a non-blocking stretch ticket. Close the epic only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
