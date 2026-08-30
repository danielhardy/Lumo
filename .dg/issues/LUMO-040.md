---
id: LUMO-040
title: Epic 7 — LUTs as an optional Look stage
type: feature
status: backlog
priority: high
labels:
  - mvp
  - epic
  - epic:lut
  - phase:7
created: 2026-08-30T18:30:30.653Z
updated: 2026-08-30T18:31:55.559Z
depends_on:
  - LUMO-041
  - LUMO-042
  - LUMO-043
order: ssssssso
board: product
---

## Objective

Preserve LUTzy's mature cube tooling while making a LUT an optional, durable operation within the broader editor.

## MVP outcome

- [ ] None is a first-class state and LUT IDs survive scans/relaunch.
- [ ] The Look browser remains fast and searchable.
- [ ] Preview/export, copy/paste, undo, and persistence agree without regressing LUT derivation.

## Child tickets

- LUMO-041 — Harden optional LUT identity and resolution across persisted edits
- LUMO-042 — Reframe the LUT library as a Look inspector
- LUMO-043 — Verify LUT behavior through persistence, copy/paste, and full export

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
