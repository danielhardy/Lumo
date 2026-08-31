---
id: LUMO-021
title: Build a virtualized library grid with multi-selection
type: task
status: claimed
priority: urgent
labels:
  - mvp
  - epic:library
  - phase:3
created: 2026-08-30T18:30:24.083Z
updated: 2026-08-31T16:58:09.943Z
depends_on:
  - LUMO-019
  - LUMO-020
estimate: 5
order: w
board: product
claim:
  actor: codex
  session: 01MTHHFAMVLJ9PSALI
  claimed_at: 2026-08-31T16:58:09.943Z
  expires_at: 2026-08-31T17:58:09.943Z
  model: gpt-5.6-luna
---

## Objective

Provide a fast grid-first browsing surface for hundreds or thousands of assets.

## Context

Part of **Epic 3 — Folder library and rapid culling**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Use lazy/virtualized layout with selection and active-photo distinction.
- Request thumbnails only for visible and near-visible cells.
- Support click, command-click, shift-range, and select-all semantics.
- Show rating/flag state without obscuring the image.

## Acceptance criteria

- [ ] A 1,000-item library does not instantiate or decode every cell eagerly.
- [ ] Selection semantics match native macOS expectations.
- [ ] Scrolling remains responsive while thumbnails arrive.
- [ ] Opening the active item enters Edit without waiting for full RAW decode.

## Verification

- Add selection model tests and profile a synthetic 1,000-item grid.

## Out of scope

- Map, face, or album views.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
