---
id: LUMO-047
title: Unify before/after comparison for every edit stage
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:32.976Z
updated: 2026-08-30T18:30:50.415Z
depends_on:
  - LUMO-045
  - LUMO-014
estimate: 3
order: xu8n1fu3
board: product
---

## Objective

Make Space-hold and side-by-side comparison work for Light, Color, Effects, LUT, and crop policy with an explicit baseline.

## Context

Part of **Epic 8 — Image-centric editor experience**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define before as developed source with the documented RAW baseline.
- Use shared cached intermediates so comparison is cheap.
- Prevent stale original renders during photo/develop changes.
- Support temporary Space behavior without stealing text-field input.

## Acceptance criteria

- [ ] Comparison is available exactly when a visible look-stage edit exists.
- [ ] Both views share orientation, crop policy, zoom, and color handling.
- [ ] Holding/releasing Space is immediate from cache where possible.
- [ ] Keyboard handling respects focused text controls and system shortcuts.

## Verification

- Add comparison-availability, baseline, stale-render, and shortcut-focus tests.

## Out of scope

- Reference-photo comparison.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
