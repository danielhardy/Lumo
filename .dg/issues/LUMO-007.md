---
id: LUMO-007
title: Isolate edit state per photo during navigation
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:19.185Z
updated: 2026-08-30T18:30:38.778Z
depends_on:
  - LUMO-006
estimate: 5
order: 51fu8n1f
board: product
---

## Objective

Replace the current carry-forward document behavior with per-photo edit sessions while preserving optional look auditioning as an explicit action.

## Context

Part of **Epic 1 — Durable per-photo edit domain**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Associate a document with stable asset identity.
- Load/save the active document on filmstrip and grid navigation.
- Seed RAW develop from each file's own as-shot capabilities.
- Prevent late renders from the previous selection from publishing over the new photo.

## Acceptance criteria

- [ ] Edits on photo A do not silently appear on photo B.
- [ ] Returning to A restores its unsaved in-session edits.
- [ ] Each RAW starts from its own as-shot develop defaults.
- [ ] Rapid navigation cannot publish stale preview, histogram, or capability state.

## Verification

- Add fake-engine navigation race tests and mixed RAW/standard session tests.

## Out of scope

- Disk persistence.
- Copy/paste UI.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
