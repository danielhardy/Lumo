---
id: LUMO-043
title: Verify LUT behavior through persistence, copy/paste, and full export
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:lut
  - phase:7
created: 2026-08-30T18:30:31.625Z
updated: 2026-08-30T18:30:49.269Z
depends_on:
  - LUMO-042
  - LUMO-010
estimate: 3
order: uyk5rcyf
board: product
---

## Objective

Close cross-workflow regressions caused by moving LUTs from global app state into per-photo edits.

## Context

Part of **Epic 7 — LUTs as an optional Look stage**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Exercise 0%, partial, and full intensity at preview/export quality.
- Cover edit persistence, undo/redo, single and multi-photo copy/paste.
- Preserve working-space and derived-LUT invariants.

## Acceptance criteria

- [ ] Preview and export apply the same LUT and intensity.
- [ ] LUT edits survive navigation and relaunch per photo.
- [ ] Copy/paste and undo affect exactly the intended photos.
- [ ] Existing cube parser, working-space, and derive invariance tests remain green.

## Verification

- Add end-to-end workflow tests around the fake and real render seams.

## Out of scope

- New LUT formats.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
