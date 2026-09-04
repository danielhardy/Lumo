---
id: LUMO-174
title: "Audit: reduce large-library SwiftUI invalidation and projection work"
type: task
status: done
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
updated: 2026-09-04T14:42:43.130Z
order: zzzzzzzv
board: product
claim:
  actor: codex
  session: 01MTMQ5HSK58GL4TWK
  claimed_at: 2026-09-04T09:01:20.084Z
  expires_at: 2026-09-04T10:01:20.084Z
  model: gpt-5.6-luna
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


### Comment — codex @ 2026-09-04T10:18:35.298Z

Implemented revision-keyed collection projection caching, one-snapshot grid/filmstrip bodies, and item-scoped ObservableObject cells so thumbnail updates avoid broad collection invalidation. Added 1k/10k projection benchmark and publisher-isolation regressions. Verification: swift test --filter CollectionProjectionPerformanceTests (3 passed); swift test --filter Library (48 passed, 1 opt-in benchmark skipped); swift test --filter PhotosImport (14 passed, 1 opt-in benchmark skipped); git diff --check passed. Full swift test built and ran 741 tests with 740 passing, 34 skipped, and one unrelated existing adjustment-render timeout.
