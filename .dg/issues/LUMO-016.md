---
id: LUMO-016
title: Instrument the end-to-end image workflow with signposts and metrics
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:22.463Z
updated: 2026-08-30T18:30:40.810Z
depends_on:
  - LUMO-013
  - LUMO-014
estimate: 3
order: bipx4bio
board: product
---

## Objective

Make performance claims falsifiable with signposts for launch, scan, decode, render, cache, photo switch, histogram, and export.

## Context

Part of **Epic 2 — Render orchestration, caching, and observability**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Create centralized OSLog categories and signpost interval helpers.
- Attach source/quality identifiers that aid diagnosis without logging private paths.
- Measure cache hit/miss and cancellation/coalescing counts.
- Document an Instruments capture recipe and target thresholds.

## Acceptance criteria

- [ ] Every required stage emits balanced signpost intervals.
- [ ] Logs do not expose full user paths or metadata by default.
- [ ] A developer can capture photo-switch and slider latency using documented steps.
- [ ] Metrics distinguish interactive from settled/export work.

## Verification

- Add lightweight signpost helper tests where possible and manually inspect an Instruments trace.

## Out of scope

- Analytics upload.
- Claims that targets are met before profiling.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
