---
id: LUMO-030
title: Implement As Shot and RAW-aware white balance behavior
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:color
  - phase:5
created: 2026-08-30T18:30:27.022Z
updated: 2026-08-30T18:30:44.750Z
depends_on:
  - LUMO-007
  - LUMO-024
estimate: 5
order: llllllli
board: product
---

## Objective

Unify the existing RAW develop and post-render temperature controls into a clear user-facing white-balance workflow.

## Context

Part of **Epic 5 — White balance, mixer, and color grading**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define As Shot seed/reset per asset.
- Use CIRAWFilter RAW-domain controls when supported.
- Specify standard-image fallback and capability-disabled behavior.
- Spike Auto only if an Apple API provides a reliable, testable result; otherwise record it as deferred.

## Acceptance criteria

- [ ] As Shot restores the file-specific decoder baseline.
- [ ] Temperature warms rightward and tint direction is consistent across RAW/standard images.
- [ ] Unsupported RAW controls are disabled rather than simulated silently.
- [ ] Navigating photos never carries another RAW's white-balance seed.

## Verification

- Add mixed-source, capability, As Shot, direction, and navigation tests.

## Out of scope

- Custom machine-learning auto white balance.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
