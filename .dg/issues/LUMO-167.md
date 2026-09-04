---
id: LUMO-167
title: "Audit: cap and stream user-provided Cube LUT parsing"
type: bug
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - security
  - robustness
  - lut
  - audit
created: 2026-09-03T23:28:48.865Z
updated: 2026-09-03T23:28:48.865Z
order: zzzv
board: product
---

## Objective

Bound resource use while parsing user-provided `.cube` and `.look` LUT files.

## Context

`CubeLUT` loads the entire file into a `String` and splits every line before validating the declared size and row count. A malformed or unexpectedly large user-selected file can consume excessive memory and CPU before it is rejected.

## Acceptance criteria

- [ ] File size, line length, metadata volume, and supported LUT dimensions are bounded before allocation.
- [ ] Parsing is incremental or otherwise avoids retaining the complete source text and line array.
- [ ] Parsing stops after the expected `size³` rows and rejects trailing excess safely.
- [ ] Tests cover oversized files, oversized lines, excessive metadata, truncated data, and valid 65³ files.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
