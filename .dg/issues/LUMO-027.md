---
id: LUMO-027
title: Implement a versioned RGB tone curve model and renderer
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:light
  - phase:4
created: 2026-08-30T18:30:26.080Z
updated: 2026-08-30T18:30:43.411Z
depends_on:
  - LUMO-024
estimate: 5
order: jfu8n1fr
board: product
---

## Objective

Add a compact, editable tone curve with deterministic interpolation suitable for persistence and later UI editing.

## Context

Part of **Epic 4 — Photographic Light controls**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define ordered normalized control points and validation rules.
- Choose GPU-backed interpolation that is monotonic when the points are monotonic.
- Start with a master RGB curve; leave channel curves extensible if not shipped.
- Include curve state in hashes, copy/paste, undo, and persistence.

## Acceptance criteria

- [ ] Default diagonal is identity.
- [ ] Invalid/duplicate/out-of-range points normalize or fail predictably.
- [ ] A monotonic curve cannot create reversals due to interpolation.
- [ ] Preview and full-resolution renders agree within test tolerance.

## Verification

- Add model validation, interpolation, identity, monotonicity, and parity tests.

## Out of scope

- Parametric curve regions unless justified.
- Local curves.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
