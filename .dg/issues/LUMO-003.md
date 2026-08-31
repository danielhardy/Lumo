---
id: LUMO-003
title: Preserve upstream attribution and rewrite product documentation for Lumo
type: task
status: verification
priority: high
agent: opencode
labels:
  - mvp
  - epic:identity
  - phase:0
created: 2026-08-30T18:30:17.974Z
updated: 2026-08-31T01:18:37.384Z
depends_on:
  - LUMO-002
estimate: 2
order: n
board: product
---

## Objective

Retain the MIT license and an explicit fork notice while replacing the LUT-centric product description with Lumo's MVP workflow and accurate build instructions.

## Context

Part of **Epic 0 — Product identity and clean baseline**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Keep LICENSE intact and add a concise upstream/fork notice.
- Rewrite README product identity, workflow, structure, commands, and capability status.
- Separate historical LUTzy references from current Lumo identifiers.

## Acceptance criteria

- [ ] MIT attribution and LUTzy origin are discoverable from the repository root.
- [ ] README describes Lumo rather than presenting the product as LUTzy.
- [ ] Every documented command/path matches the renamed tree.

## Verification

- Follow the documented build/test commands.
- Search documentation for stale non-historical identifiers.

## Out of scope

- Marketing site or App Store copy.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
