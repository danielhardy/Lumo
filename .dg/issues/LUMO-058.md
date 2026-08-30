---
id: LUMO-058
title: Profile and fix the highest-impact measured bottlenecks
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:quality
  - phase:10
created: 2026-08-30T18:30:37.263Z
updated: 2026-08-30T18:30:54.949Z
depends_on:
  - LUMO-057
  - LUMO-056
estimate: 8
order: zzx
board: product
---

## Objective

Use Instruments evidence to address the bottlenecks that prevent the MVP targets, with before/after proof.

## Context

Part of **Epic 10 — Image quality, performance, and MVP release gate**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Inspect main-thread stalls, render/decode time, cache behavior, thumbnail queues, memory growth, and export throughput.
- Prioritize user-perceived latency and >100 ms main-thread stalls.
- Make narrow fixes and rerun the same scenario after each change.
- Open separate bugs for lower-impact findings rather than expanding scope.

## Acceptance criteria

- [ ] No known >100 ms main-thread stall remains in the core workflow without a documented blocker.
- [ ] Cached photo switch, slider response, and interactive render targets are met or have evidence-backed exceptions.
- [ ] Memory is bounded in 1,000-photo navigation and long batch export.
- [ ] Before/after measurements accompany each optimization.

## Verification

- Repeat benchmark scenarios and inspect Time Profiler, Core Image, and memory traces.

## Out of scope

- Micro-optimizations without measured benefit.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
