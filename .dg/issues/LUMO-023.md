---
id: LUMO-023
title: Epic 4 — Photographic Light controls
type: feature
status: backlog
priority: urgent
labels:
  - mvp
  - epic
  - epic:light
  - phase:4
created: 2026-08-30T18:30:24.789Z
updated: 2026-08-30T18:31:55.013Z
depends_on:
  - LUMO-024
  - LUMO-025
  - LUMO-026
  - LUMO-027
  - LUMO-028
order: gk5rcyk3
board: product
---

## Objective

Deliver predictable, real-time Exposure, Contrast, Highlights, Shadows, Whites, Blacks, and Tone Curve controls on the shared pipeline.

## MVP outcome

- [ ] Every Light control has photographer-facing units and a tested neutral.
- [ ] Preview and export agree.
- [ ] Highlight/shadow endpoint behavior is useful on representative photographs at interactive speed.

## Child tickets

- LUMO-024 — Define the Light adjustment model, ranges, order, and migration
- LUMO-025 — Refine Exposure, Contrast, Highlights, and Shadows behavior
- LUMO-026 — Implement Whites and Blacks endpoint controls
- LUMO-027 — Implement a versioned RGB tone curve model and renderer
- LUMO-028 — Ship the Light inspector with reset and interaction semantics

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
