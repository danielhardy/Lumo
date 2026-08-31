---
id: LUMO-011
title: Epic 2 — Render orchestration, caching, and observability
type: feature
status: done
priority: urgent
labels:
  - mvp
  - epic
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:20.810Z
updated: 2026-08-31T14:19:09.177Z
depends_on:
  - LUMO-012
  - LUMO-013
  - LUMO-014
  - LUMO-015
  - LUMO-016
order: a0
board: product
commits:
  - ee28124
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

### Comment — codex @ 2026-08-31T14:19:03.262Z

Implemented Epic 2 in commits 1c57516 and ee28124. Integrated explicit RenderRequest/RenderResult quality tiers, cancellation and coalescing through PreviewCoordinator, bounded render/developed-source/thumbnail caches with complete keys and memory-pressure handling, priority-aware thumbnail scheduling with backpressure and adjacent-photo reprioritization, and OSLog signposts/metrics with an Instruments capture guide. Verification: swift test passed (332 executed, 20 expected skips, 0 failures); swift build -c release passed; git diff --check passed; dg validate passed with only the known model/context warnings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T14:19:09.175Z: Epic 2 render orchestration shipped with unified quality-tier requests, coalesced cancellation, bounded caches, priority-aware thumbnail scheduling, and end-to-end signposts/metrics. Full tests and release build pass.
