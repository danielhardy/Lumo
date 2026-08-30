---
id: LUMO-048
title: Coalesce histogram updates from the displayed render
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:33.358Z
updated: 2026-08-30T18:30:50.785Z
depends_on:
  - LUMO-045
  - LUMO-013
estimate: 3
order: yk5rcyk0
board: product
---

## Objective

Adapt the inherited histogram so it reflects the current displayed edit without competing with slider responsiveness.

## Context

Part of **Epic 8 — Image-centric editor experience**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Compute from the same displayed revision and color pipeline.
- Cancel/coalesce transient histogram work.
- Gate work when the histogram is hidden.
- Prevent results from an older photo/edit publishing late.

## Acceptance criteria

- [ ] Histogram changes after settled edits and matches before/after state.
- [ ] Hidden histogram causes no computation.
- [ ] Rapid slider input does not queue histogram work per tick.
- [ ] Late results cannot replace the current revision.

## Verification

- Extend fake-engine histogram gating, coalescing, revision, and comparison tests.

## Out of scope

- Clipping overlays unless separately prioritized.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
