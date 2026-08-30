---
id: LUMO-011
title: Epic 2 — Render orchestration, caching, and observability
type: feature
status: backlog
priority: urgent
labels:
  - mvp
  - epic
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:20.810Z
updated: 2026-08-30T18:31:54.630Z
depends_on:
  - LUMO-012
  - LUMO-013
  - LUMO-014
  - LUMO-015
  - LUMO-016
order: 7x4bipx3
board: product
---

## Objective

Build on the existing actor renderer and shared preview/export pipeline to deliver responsive quality tiers, cancellation, bounded caches, priorities, and measurements.

## MVP outcome

- [ ] Interactive work supersedes stale renders and settles to a high-quality preview.
- [ ] Caches are bounded and keyed by all material inputs.
- [ ] Signposts and repeatable benchmarks expose latency, cache, memory, and export behavior.

## Child tickets

- LUMO-012 — Expand rendering into explicit request, result, and quality tiers
- LUMO-013 — Coalesce interactive renders and settle to final preview quality
- LUMO-014 — Add bounded thumbnail, developed-source, and preview caches
- LUMO-015 — Schedule visible, adjacent, grid, and background image work by priority
- LUMO-016 — Instrument the end-to-end image workflow with signposts and metrics

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
