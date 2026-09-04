---
id: LUMO-169
title: "Audit: restore repository and CI quality guardrails"
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ci
  - dx
  - quality
  - audit
created: 2026-09-03T23:28:50.102Z
updated: 2026-09-03T23:28:50.102Z
order: zzzy
board: product
---

## Objective

Restore reliable repository, formatting, documentation, and CI quality guardrails.

## Context

The README and living review documents contain stale test counts and historical architecture names. There is no repository Swift-format configuration, packaging can mutate tracked icon assets, large RAW fixtures are committed without LFS despite guidance saying otherwise, and CI lacks signature checks, UI smoke coverage, and useful fast/slow test separation.

## Acceptance criteria

- [ ] README and living audit/spec documents match the current product name, architecture, and test counts.
- [ ] A checked-in Swift-format configuration matches the house style and CI reports actionable changed-file violations.
- [ ] Packaging generates build artifacts without modifying tracked source files.
- [ ] RAW fixture storage/privacy/licensing is documented and the repository strategy is consistent with project guidance.
- [ ] CI verifies signed bundles and includes a minimal application-level smoke path for launch, open, settings/menu, and export flows.
- [ ] Slow hardware/RAW coverage is separated or parallelized without reducing required regression coverage.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
