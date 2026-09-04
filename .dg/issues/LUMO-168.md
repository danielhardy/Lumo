---
id: LUMO-168
title: "Audit: split oversized application and rendering coordinators"
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - maintainability
  - architecture
  - dx
  - audit
created: 2026-09-03T23:28:49.685Z
updated: 2026-09-03T23:28:49.685Z
order: zzzx
board: product
---

## Objective

Reduce architectural coupling by splitting the oversized application, collection, rendering, and export coordinators along stable responsibilities.

## Context

`AppViewModel` is approximately 2,929 lines and owns imports, source sessions, library commands, preview/comparison/histogram state, crop/navigation, export bridges, Look workflows, and persistence. `RenderEngine`, `ImageCollection`, and `RenderPipeline` are each over 1,200 lines and combine multiple independently changing concerns. Broad observation and actor boundaries make regressions and unnecessary UI invalidation easier to introduce.

## Acceptance criteria

- [ ] Responsibilities and ownership boundaries are documented before moving code.
- [ ] Source/import, preview session, persistence, collection/scanning, and export concerns have independently testable seams.
- [ ] Render stages and GPU/cache lifecycle are separated behind a small façade without changing rendering behavior.
- [ ] Views observe the narrowest state object needed for their behavior.
- [ ] Existing public/compatibility APIs are intentionally retained, migrated, or removed with tests updated accordingly.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
