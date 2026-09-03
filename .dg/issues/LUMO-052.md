---
id: LUMO-052
title: Export current or selected photos from originals and saved edits
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:export
  - phase:9
created: 2026-08-30T18:30:35.046Z
updated: 2026-09-02T16:58:33.004Z
depends_on:
  - LUMO-051
  - LUMO-021
  - LUMO-041
estimate: 5
order: zzzx
board: product
commits:
  - 92e95ec
---

## Objective

Route single and selected-image export through the shared full-resolution pipeline, never through preview bitmaps.

## Context

Part of **Epic 9 — Reliable full-resolution export**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Resolve each asset's original source and persisted adjustment record.
- Render at export quality with selected sizing/color options.
- Use security-scoped destination access correctly.
- Keep export work off the main actor.

## Acceptance criteria

- [ ] Output dimensions come from original/full-resolution policy, not preview size.
- [ ] Each selected photo uses its own saved edits and LUT.
- [ ] Current export affects one photo; Selected affects exactly the selection.
- [ ] RAW originals remain unchanged.

## Verification

- Extend full-resolution, per-photo edit, selection, orientation, and sandbox tests.

## Out of scope

- Remote/cloud destinations.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T16:58:32.998Z: Implemented current and selected full-resolution export from original-backed sources. Batch items now carry stable asset identity, optional security-scoped source bookmarks, and per-photo live snapshots; unopened assets resolve persisted EditDocument records and LUTs through the app's store/library. Added selected-only UI/menu routing, scoped destination/source access, and regressions for selection, per-photo persistence, full scale, and original sources. Verification: swift test (624 passed, 13 expected skips), swift build -c release, git diff --check, dg validate.
