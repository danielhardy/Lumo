---
id: LUMO-053
title: Add batch progress, cancellation, collision handling, and failure isolation
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:export
  - phase:9
created: 2026-08-30T18:30:35.423Z
updated: 2026-08-30T18:30:52.688Z
depends_on:
  - LUMO-052
  - LUMO-015
estimate: 5
order: zy
board: product
---

## Objective

Make long selected exports controllable and trustworthy without aborting the whole run for one bad file.

## Context

Part of **Epic 9 — Reliable full-resolution export**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Report completed/total/current item and final success/failure/cancel summary.
- Cancel between expensive stages and clean incomplete outputs safely.
- Use deterministic collision-resistant naming.
- Bound concurrent full-resolution work to protect memory.

## Acceptance criteria

- [ ] Cancel stops new work and leaves completed valid files intact.
- [ ] One failed source is reported and remaining files continue.
- [ ] No two selected assets overwrite one another.
- [ ] Memory does not scale linearly with batch length.

## Verification

- Add failure, cancellation, collision, partial-output, and bounded-concurrency tests.

## Out of scope

- Background exports after app quit.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
