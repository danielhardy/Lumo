---
id: LUMO-042
title: Reframe the LUT library as a Look inspector
type: task
status: backlog
priority: medium
labels:
  - mvp
  - epic:lut
  - phase:7
created: 2026-08-30T18:30:31.224Z
updated: 2026-08-30T18:30:48.888Z
depends_on:
  - LUMO-041
  - LUMO-009
estimate: 5
order: u8n1fu8i
board: product
---

## Objective

Retain nested folders, search, intensity, and keyboard browsing in an optional Look section integrated with the editor.

## Context

Part of **Epic 7 — LUTs as an optional Look stage**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Add an explicit None row and clear selected state.
- Retain recursive folders, search, counts, and up/down auditioning where focus rules permit.
- Make selection/intensity per-photo and undoable.
- Keep derived LUT creation accessible without dominating the edit workflow.

## Acceptance criteria

- [ ] A user can edit fully without configuring a LUT folder.
- [ ] Selecting None clears the visual effect and persists.
- [ ] Search/folder grouping and keyboard auditioning remain functional.
- [ ] Look controls participate in resets without affecting unrelated panels.

## Verification

- Add state/reset/navigation tests and regression-smoke the derive workflow.

## Out of scope

- Online LUT marketplace.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
