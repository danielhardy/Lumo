---
id: LUMO-040
title: Epic 7 — LUTs as an optional Look stage
type: feature
status: claimed
priority: high
labels:
  - mvp
  - epic
  - epic:lut
  - phase:7
created: 2026-08-30T18:30:30.653Z
updated: 2026-09-01T14:09:17.847Z
depends_on:
  - LUMO-041
  - LUMO-042
  - LUMO-043
order: a0
board: product
claim:
  actor: codex
  session: 01MTIQTZBRPR9C7YPD
  claimed_at: 2026-09-01T14:09:17.847Z
  expires_at: 2026-09-01T15:09:17.847Z
  model: gpt-5.6-luna
---

## Objective

Preserve LUTzy's mature cube tooling while making a LUT an optional, durable operation within the broader editor.

## MVP outcome

- [x] None is a first-class state and LUT IDs survive scans/relaunch.
- [x] The Look browser remains fast and searchable.
- [x] Preview/export, copy/paste, undo, and persistence agree without regressing LUT derivation.

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
