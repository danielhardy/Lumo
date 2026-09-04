---
id: LUMO-173
title: "Audit: move folder scan I/O off main actor and remove quadratic work"
type: task
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - performance
  - library
  - scanning
  - audit
created: 2026-09-03T23:31:00.000Z
updated: 2026-09-03T23:31:00.000Z
order: zzzzc
board: product
---

## Objective

Keep folder discovery responsive by moving file identity work off the main actor and making batch merge work subquadratic.

## Context

Although discovery is streamed, batch publication constructs file-backed assets on `@MainActor`. Identity/fingerprint work performs file reads, while each item scans the accumulated array for duplicates and triggers a full sort after each batch. Large, removable, or network-backed folders can visibly block the UI.

## Acceptance criteria

- [ ] File resource queries and fingerprints are computed once off-main before publication.
- [ ] Duplicate detection uses a set or equivalent indexed structure.
- [ ] Batch ordering avoids repeated full-array sorting while preserving deterministic library order.
- [ ] Cancellation and stale-scan generation behavior remain intact.
- [ ] Benchmarks or instrumentation cover realistic 1k/10k item folders.
