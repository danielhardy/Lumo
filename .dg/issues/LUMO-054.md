---
id: LUMO-054
title: Add optional Apple Photos delivery after file export is stable
type: task
status: backlog
priority: low
labels:
  - mvp
  - stretch
  - epic:export
  - phase:9
created: 2026-08-30T18:30:35.848Z
updated: 2026-08-30T18:33:00.789Z
depends_on:
  - LUMO-053
estimate: 5
order: zz
board: product
---

## Objective

Allow final exports to be saved to Photos and optionally an album without coupling core rendering to PhotoKit.

## Context

Part of **Epic 9 — Reliable full-resolution export**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Reuse completed encoded files/data from the reliable export path.
- Request authorization at the point of use and handle limited/denied states.
- Create or select an optional destination album.
- Report partial failures separately from render failures.

## Acceptance criteria

- [ ] Authorized exports appear in Photos with optional album placement.
- [ ] Denied/limited authorization has clear recovery guidance.
- [ ] PhotoKit failure does not corrupt or remove successful file output.
- [ ] Core export tests run without Photos authorization.

## Verification

- Unit-test the coordinator behind an adapter and manually smoke-test authorization states.

## Out of scope

- Photos library editing or synchronization.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
