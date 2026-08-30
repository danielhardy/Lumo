---
id: LUMO-015
title: Schedule visible, adjacent, grid, and background image work by priority
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:22.050Z
updated: 2026-08-30T18:30:40.451Z
depends_on:
  - LUMO-013
  - LUMO-014
estimate: 5
order: assssssr
board: product
---

## Objective

Ensure thumbnail and precache work yields to active editing and photo navigation.

## Context

Part of **Epic 2 — Render orchestration, caching, and observability**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define priorities for active editor, adjacent filmstrip, visible grid, and background work.
- Apply backpressure to folder-scale thumbnail generation.
- Cancel work that scrolls out of relevance where safe.
- Avoid serializing all thumbnails behind the render actor's GPU-critical path.

## Acceptance criteria

- [ ] Active editor work starts ahead of queued background thumbnails.
- [ ] Thumbnail production has a bounded concurrency limit.
- [ ] Fast scrolling/navigation does not leave an unbounded obsolete queue.
- [ ] Adjacent-photo preparation improves perceived switching without starving the current photo.

## Verification

- Add scheduler ordering, cancellation, and bounded-queue tests.

## Out of scope

- Distributed rendering.
- Speculative work without a measurable consumer.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
