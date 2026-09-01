---
id: LUMO-026
title: Implement Whites and Blacks endpoint controls
type: task
status: done
priority: high
labels:
  - mvp
  - epic:light
  - phase:4
created: 2026-08-30T18:30:25.693Z
updated: 2026-08-31T19:44:06.385Z
depends_on:
  - LUMO-024
estimate: 5
order: t
board: product
commits:
  - 2cbc904
---

## Objective

Add independent high-end and low-end tonal controls with useful rolloff rather than duplicate brightness/contrast behavior.

## Context

Part of **Epic 4 — Photographic Light controls**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Implement GPU-backed white-point/high-end and black-point/low-end stages.
- Preserve alpha, extent, orientation, and finite output.
- Place them deterministically relative to other Light controls.

## Acceptance criteria

- [ ] Whites predominantly affect the upper range and Blacks the lower range.
- [ ] Neutral values are exact no-ops.
- [ ] Moderate changes do not introduce NaN, banding, or unintended extent changes.
- [ ] Preview/export parity tests pass.

## Verification

- Add gradient-region, clipping, neutral, extent, and parity tests.

## Out of scope

- HDR display mastering.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T19:44:06.383Z: Implemented independent GPU-backed Whites and Blacks endpoint tone stages with deterministic Light ordering, finite/monotonic rolloff, clipping and neutral/extent/parity coverage. Full swift test, release build, and dg validate pass.
