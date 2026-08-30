---
id: LUMO-004
title: Establish the post-rename build and regression baseline
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:identity
  - phase:0
created: 2026-08-30T18:30:18.315Z
updated: 2026-08-30T18:30:38.423Z
depends_on:
  - LUMO-002
  - LUMO-003
estimate: 3
order: 2voha2vo
board: product
---

## Objective

Prove the rename preserved behavior and record the exact build, test, and capability baseline future tickets must protect.

## Context

Part of **Epic 0 — Product identity and clean baseline**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Run debug build, full tests, and release build.
- Triage only rename-related failures.
- Document retained inherited capabilities and known pre-existing gaps without broad cleanup.

## Acceptance criteria

- [ ] Debug build, full tests, and release build are green on the supported toolchain.
- [ ] A concise baseline record names test count, toolchain, retained capabilities, and known gaps.
- [ ] CI uses the renamed schemes/targets and remains green.

## Verification

- Run swift build, swift test, and swift build -c release.
- Inspect CI configuration for stale target names.

## Out of scope

- Fixing unrelated legacy defects.
- Performance tuning.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
