---
id: LUMO-013
title: Coalesce interactive renders and settle to final preview quality
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:21.357Z
updated: 2026-08-30T18:30:39.881Z
depends_on:
  - LUMO-012
estimate: 5
order: 9cyk5rcx
board: product
---

## Objective

Introduce a coordinator that cancels superseded slider renders, prioritizes the visible image, and publishes a settled preview after interaction ends.

## Context

Part of **Epic 2 — Render orchestration, caching, and observability**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Model gesture/burst lifecycle separately from the renderer actor.
- Issue viewport-sized interactive work during manipulation.
- Cancel/coalesce stale work and render preview quality on settle.
- Guard every publication with source and revision identity.

## Acceptance criteria

- [ ] Rapid 0.1→0.5 input converges on 0.5 without a five-render queue.
- [ ] UI state publication remains main-actor-only while decoding/rendering does not.
- [ ] A settled render replaces interactive output.
- [ ] Navigation and edits cannot display stale results.

## Verification

- Add deterministic fake-renderer cancellation, coalescing, settle, and stale-publication tests.

## Out of scope

- GPU filter design.
- Display refresh synchronization beyond the MVP target.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
