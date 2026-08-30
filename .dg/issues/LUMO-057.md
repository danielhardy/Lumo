---
id: LUMO-057
title: Build repeatable large-library and render benchmark scenarios
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:quality
  - phase:10
created: 2026-08-30T18:30:36.847Z
updated: 2026-08-30T18:30:54.552Z
depends_on:
  - LUMO-046
  - LUMO-048
  - LUMO-053
  - LUMO-016
estimate: 5
order: zzv
board: product
---

## Objective

Measure launch, scanning, thumbnails, switch latency, slider response, interactive FPS, cache behavior, memory, decode, and export throughput.

## Context

Part of **Epic 10 — Image quality, performance, and MVP release gate**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Provide scenarios for 100, 500, and 1,000+ images plus 24 MP and 40–50+ MP sources.
- Use signpost-driven scripts/checklists with warm/cold cache distinctions.
- Record hardware, OS, build configuration, and dataset characteristics.
- Avoid asserting universal wall-clock thresholds in flaky unit tests.

## Acceptance criteria

- [ ] Each target metric has a repeatable measurement procedure.
- [ ] Results distinguish UI input latency from render completion.
- [ ] Memory is sampled across long navigation and export sessions.
- [ ] A baseline report identifies the highest-impact bottlenecks.

## Verification

- Run the suite on at least one modern Apple Silicon Mac and archive summarized results.

## Out of scope

- Speculative optimization.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
