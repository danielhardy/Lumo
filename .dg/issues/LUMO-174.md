---
id: LUMO-174
title: "Audit: reduce large-library SwiftUI invalidation and projection work"
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - performance
  - swiftui
  - library
  - audit
created: 2026-09-03T23:31:00.000Z
updated: 2026-09-03T23:31:00.000Z
order: zzzzd
board: product
---

## Objective

Limit whole-library SwiftUI recomputation when individual thumbnails or metadata arrive.

## Context

`ImageCollection` derives filtered indices and thumbnail entries by walking the full item array. Grid and filmstrip views request those projections multiple times, and each thumbnail mutation publishes the collection observed by broad view hierarchies. Thousands of items can therefore turn one cell update into O(n) projection and layout work.

## Acceptance criteria

- [ ] Filtered/thumbnail projections are memoized by a clear collection and filter revision.
- [ ] Each view body computes a projection once and reuses it.
- [ ] Cell-level thumbnail updates do not invalidate unrelated library rows.
- [ ] Selection, ordering, filtering, and incremental import semantics remain unchanged.
- [ ] Instruments or benchmark coverage demonstrates bounded update work for 1k/10k item libraries.
