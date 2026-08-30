---
id: LUMO-001
title: Epic 0 — Product identity and clean baseline
type: feature
status: backlog
priority: urgent
labels:
  - mvp
  - epic
  - epic:identity
  - phase:0
created: 2026-08-30T18:25:25.896Z
updated: 2026-08-30T18:31:54.270Z
depends_on:
  - LUMO-002
  - LUMO-003
  - LUMO-004
order: 0px4bipx
board: product
---

## Objective

Complete the fork cleanup before feature expansion, with Lumo identity, preserved LUTzy attribution, and a trusted green baseline.

## MVP outcome

- [ ] All product/package identifiers use Lumo except historical attribution.
- [ ] Update/Revised README that explains the project intention and methodology (an expeirement in not just agent built but agent lead software development. Including DispatchGraph)
- [ ] Debug and release builds plus the applicable test suite pass.
- [ ] Existing RAW, LUT, thumbnail, Photos, metadata, histogram, and export capabilities remain intact.

## Child tickets

- LUMO-002 — Rename the LUTzy fork to Lumo across package and app surfaces
- LUMO-003 — Preserve upstream attribution and rewrite product documentation for Lumo
- LUMO-004 — Establish the post-rename build and regression baseline

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
