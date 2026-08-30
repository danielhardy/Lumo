---
id: LUMO-038
title: Implement deterministic resolution-aware photographic grain
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:effects
  - phase:6
created: 2026-08-30T18:30:29.865Z
updated: 2026-08-30T18:30:47.188Z
depends_on:
  - LUMO-024
  - LUMO-014
estimate: 8
order: rcyk5rcu
board: product
---

## Objective

Add Amount, Size, and Roughness grain that remains visually stable during rerenders and scales appropriately at export.

## Context

Part of **Epic 6 — Photographic effects**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Derive deterministic seed from stable asset/pipeline inputs without changing on slider redraw.
- Use GPU noise synthesis and shape it beyond uniform digital noise.
- Define size in normalized/physical output terms so preview is representative of export.
- Avoid caching random frame-dependent outputs.

## Acceptance criteria

- [ ] Identical source/edit/quality requests reproduce the same grain pattern.
- [ ] Changing unrelated UI state does not make grain dance.
- [ ] Amount, Size, and Roughness are independently measurable.
- [ ] Export grain scale matches the documented viewing-size policy.

## Verification

- Add determinism, parameter-independence, scale, cache-key, and parity tests.

## Out of scope

- Camera-specific film stock emulation.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
