---
id: LUMO-166
title: "Audit: prevent termination after failed edit persistence flush"
type: bug
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - bug
  - data-loss
  - persistence
  - audit
created: 2026-09-03T23:28:48.445Z
updated: 2026-09-03T23:28:48.445Z
order: zzzq
board: product
---

## Objective

Prevent application termination from approving a quit while edit persistence is still dirty or has failed.

## Context

`drainPersistence` keeps failed snapshots dirty, but `flushPendingWrites()` returns no success state and `LumoApp` always replies `true` after awaiting it. A disk-full, permission, or store-corruption error during quit can therefore lose edits.

## Acceptance criteria

- [ ] The termination flush reports success, failure, and cancellation distinctly.
- [ ] The app does not approve termination while dirty snapshots remain after a failed flush.
- [ ] Users receive retry and explicit quit-without-saving choices for nonrecoverable failures.
- [ ] Tests cover a failing store during `applicationShouldTerminate` and verify no data-loss approval occurs silently.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
