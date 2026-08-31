---
id: LUMO-022
title: Implement rating, pick/reject, filters, and keyboard culling
type: task
status: done
priority: high
labels:
  - mvp
  - epic:library
  - phase:3
created: 2026-08-30T18:30:24.444Z
updated: 2026-08-31T18:33:05.484Z
depends_on:
  - LUMO-021
  - LUMO-008
estimate: 5
order: a0
board: product
commits:
  - 2ab6406
---

## Objective

Enable a complete keyboard-first culling pass from the grid or focused photo.

## Context

Part of **Epic 3 — Folder library and rapid culling**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Implement P pick, X reject, 0 clear rating, and 1–5 stars.
- Add filters for picks, rejected, and minimum/exact rating with clear empty states.
- Keep navigation deterministic as a filtered set changes.
- Persist state and make changes undoable where appropriate.

## Acceptance criteria

- [ ] Keyboard commands update the focused asset immediately and advance only if the chosen workflow says so.
- [ ] Filters compose predictably and never lose underlying state.
- [ ] Filtered navigation cannot select an invisible asset.
- [ ] Culling survives relaunch.

## Verification

- Add shortcut routing, filter composition, navigation, and persistence tests.

## Out of scope

- AI ranking.
- Color labels unless separately prioritized.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T18:33:05.482Z: Implemented P/X/0/1-5 keyboard culling with pick/reject/rating persistence, bounded undo, composable flag/rating filters, filtered navigation, and grid empty states. Added focused shortcut, filter, navigation, undo, and persistence tests. Verification passed: swift test (353 passed, 20 skipped), swift build -c release, git diff --check, and dg validate.
