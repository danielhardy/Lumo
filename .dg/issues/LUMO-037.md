---
id: LUMO-037
title: Implement advanced post-crop vignette
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:effects
  - phase:6
created: 2026-08-30T18:30:29.489Z
updated: 2026-08-30T18:30:46.801Z
depends_on:
  - LUMO-024
estimate: 5
order: qn1fu8mx
board: product
---

## Objective

Add Amount, Midpoint, Roundness, Feather, and Highlights after LUT and before output transform as versioned pipeline behavior.

## Context

Part of **Epic 6 — Photographic effects**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define normalized scale-independent model.
- Implement GPU mask/compose preserving bright highlights according to the Highlights parameter.
- Account for crop/output geometry deterministically.

## Acceptance criteria

- [ ] Every subordinate parameter has an independent visible effect.
- [ ] Neutral amount is identity.
- [ ] Feathering is smooth, roundness respects aspect ratio, and no extent changes occur.
- [ ] Preview/export composition matches for the same crop.

## Verification

- Add geometry, parameter-independence, identity, and parity tests.

## Out of scope

- Lens-profile vignette correction.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
