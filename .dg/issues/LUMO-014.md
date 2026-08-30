---
id: LUMO-014
title: Add bounded thumbnail, developed-source, and preview caches
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:21.697Z
updated: 2026-08-30T18:30:40.064Z
depends_on:
  - LUMO-012
estimate: 5
order: a2voha2u
board: product
---

## Objective

Implement measurable bounded caches for expensive reusable intermediates without stale pixels or unbounded memory growth.

## Context

Part of **Epic 2 — Render orchestration, caching, and observability**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define cache keys including source identity/fingerprint, document hash, render size/quality, working color space, and pipeline version as appropriate.
- Set cost/count limits and memory-pressure eviction.
- Keep full-resolution export out of inappropriate final-image caching.
- Expose hit/miss counters for instrumentation.

## Acceptance criteria

- [ ] Repeated identical preview requests hit cache.
- [ ] Any material source/edit/size/pipeline change misses.
- [ ] Memory pressure and configured limits evict entries.
- [ ] A long navigation session has bounded cache memory.

## Verification

- Add key-completeness, eviction, invalidation, and hit/miss tests.

## Out of scope

- Persistent cloud cache.
- Premature disk cache unless measurement justifies it.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
