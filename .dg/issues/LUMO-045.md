---
id: LUMO-045
title: Build the Library/Edit navigation shell and image-centric layout
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:32.194Z
updated: 2026-08-30T18:30:49.642Z
depends_on:
  - LUMO-021
  - LUMO-007
estimate: 5
order: weeeeee9
board: product
---

## Objective

Create explicit Grid and Edit modes using the target sidebar/canvas/inspector/filmstrip structure without a giant view-model rewrite.

## Context

Part of **Epic 8 — Image-centric editor experience**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Model navigation state separately from library, edit, and render state.
- Compose existing LUT, metadata, histogram, preview, and filmstrip features into the new shell incrementally.
- Provide G, E, Enter, and obvious toolbar navigation.
- Maintain a large uninterrupted canvas at normal window sizes.

## Acceptance criteria

- [ ] Grid and Edit modes have deterministic navigation and selection handoff.
- [ ] Normal editing requires no modal dialog.
- [ ] Existing import, derive, inspector, and export entry points remain reachable.
- [ ] Layout handles supported minimum window size without overlapping controls.

## Verification

- Add navigation-state tests and manual window-size regression checks.

## Out of scope

- Album management.
- A visual clone of Lightroom.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
