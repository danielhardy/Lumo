---
id: LUMO-009
title: Implement per-photo undo and redo with gesture grouping
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:20.143Z
updated: 2026-08-30T18:30:39.178Z
depends_on:
  - LUMO-007
estimate: 5
order: 6ha2voh9
board: product
---

## Objective

Add bounded per-photo history so a complete slider drag is one undo operation and resets are reversible.

## Context

Part of **Epic 1 — Durable per-photo edit domain**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Snapshot value-state documents, not images or Core Image objects.
- Open one undo group at gesture start and close it at gesture end.
- Cover individual reset, panel reset, reset photo, LUT, and RAW develop changes.
- Clear redo on divergent edits and bound history memory.

## Acceptance criteria

- [ ] A drag through many values undoes directly to its starting value.
- [ ] Undo/redo stays isolated per photo across navigation.
- [ ] Reset operations can be undone in one step.
- [ ] History has a documented bound and never stores rendered images.

## Verification

- Add undo grouping, redo invalidation, navigation isolation, and memory-bound model tests.

## Out of scope

- Named history steps UI.
- Cross-device history.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
