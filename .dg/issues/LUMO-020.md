---
id: LUMO-020
title: Create a prioritized thumbnail service using embedded previews when useful
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:library
  - phase:3
created: 2026-08-30T18:30:23.719Z
updated: 2026-08-30T18:30:41.907Z
depends_on:
  - LUMO-018
  - LUMO-014
  - LUMO-015
estimate: 5
order: eeeeeeec
board: product
---

## Objective

Deliver fast, orientation-correct thumbnails with embedded RAW previews where beneficial and full decode fallback.

## Context

Part of **Epic 3 — Folder library and rapid culling**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Choose embedded preview versus decode based on availability and requested size.
- Integrate memory-bounded caching and scheduler priorities.
- Prevent wrong-cell publication during reuse/scrolling.
- Retain Photos-import thumbnail support.

## Acceptance criteria

- [ ] RAW thumbnails can appear without full RAW development when an adequate embedded preview exists.
- [ ] Orientation and aspect ratio match editor/export behavior.
- [ ] Cell reuse never displays another asset's thumbnail.
- [ ] Failures produce a stable placeholder and do not stall the queue.

## Verification

- Add orientation, embedded/fallback, cancellation, cache, and reuse identity tests.

## Out of scope

- Full editor-quality thumbnail rendering for every transient grid size.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
