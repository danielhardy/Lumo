---
id: LUMO-117
title: Implement real Metal presentation benchmark, archived RAW capture matrix, and tracing-overhead measurement for LUMO-114
type: task
status: done
priority: urgent
labels:
  - verification
created: 2026-09-01T23:06:54.303Z
updated: 2026-09-01T23:24:19.856Z
order: zx
board: product
commits:
  - 7e8308a
---

## Objective

Implement real Metal presentation benchmark, archived RAW capture matrix, and tracing-overhead measurement for LUMO-114

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-01T23:24:19.638Z

Implemented in commit 7e8308a. Added opt-in real CAMetalLayer drawable benchmark measuring p50/p95/p99 input-to-present, worst gap, CPU encode, GPU time, and resident-memory delta; added enabled-vs-disabled signpost overhead benchmark; added reproducible Release capture-matrix archive with standard-image rows, RAW fixture prerequisites, metadata fields, and explicit pending status. Verification: swift test (569 passed, 28 expected skips), swift build -c release passed, git diff --check passed, dg validate passed. Hardware/RAW capture execution remains opt-in because this checkout has no licensed RAW fixture and no guaranteed logged-in display.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T23:24:19.854Z: Added real Metal presentation and tracing-overhead benchmark harnesses plus reproducible archived capture matrix; all automated verification passes, with hardware/RAW runs explicitly pending required local fixtures/display.
