---
id: LUMO-172
title: "Audit: avoid materializing uncacheable high-resolution intermediates"
type: task
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - performance
  - memory
  - rendering
  - audit
created: 2026-09-03T23:31:00.000Z
updated: 2026-09-03T23:31:00.000Z
order: zzzzb
board: product
---

## Objective

Avoid expensive full-frame materialization when an intermediate cannot fit in its bounded cache.

## Context

The render engine materializes RGBA-half buffers before inserting them into caches capped at 256 MB. A 40 MP image is already about 320 MB and is therefore rendered and allocated only to be rejected. RAW and pre-LUT paths can repeat this work on later edits, with additional Metal texture memory increasing transient pressure.

## Acceptance criteria

- [ ] Estimated byte cost is checked before allocating a full-frame materialized intermediate.
- [ ] Above-budget images use a documented tiled, ROI, fused, or explicitly non-cached path.
- [ ] CPU and GPU working-set accounting is included in the relevant memory budget.
- [ ] Regression coverage verifies no repeated above-budget materialization storm for large standard and RAW sources.
- [ ] Render output parity is maintained for supported image sizes.
