---
id: LUMO-024
title: Define the Light adjustment model, ranges, order, and migration
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:light
  - phase:4
created: 2026-08-30T18:30:24.972Z
updated: 2026-08-30T18:30:42.855Z
depends_on:
  - LUMO-012
estimate: 3
order: ha2voha0
board: product
---

## Objective

Create a coherent Light model over the existing adjustment nodes without discarding working render code.

## Context

Part of **Epic 4 — Photographic Light controls**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define Exposure, Contrast, Highlights, Shadows, Whites, Blacks, and tone curve values with photographer-facing ranges.
- Specify neutral values, clamping, Codable migration, edit hash, and pipeline position.
- Map or migrate current exposure/contrast/highlight/shadow documents deliberately.

## Acceptance criteria

- [ ] Neutral Light is a true render identity.
- [ ] Old documents decode without losing their existing look.
- [ ] All values are finite, clamped, Codable, Equatable, and Sendable.
- [ ] Pipeline order and version impact are documented.

## Verification

- Add neutral, range, migration, hash, and Codable tests.

## Out of scope

- Local masks.
- Exact Adobe mathematics.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
