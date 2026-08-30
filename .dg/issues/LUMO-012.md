---
id: LUMO-012
title: Expand rendering into explicit request, result, and quality tiers
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:21.006Z
updated: 2026-08-30T18:30:39.705Z
depends_on:
  - LUMO-006
estimate: 5
order: 8n1fu8n0
board: product
---

## Objective

Evolve preview/full scale calls into a UI-independent request API supporting thumbnail, interactive, preview, full-resolution, and export qualities.

## Context

Part of **Epic 2 — Render orchestration, caching, and observability**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define Sendable RenderRequest, RenderResult, and RenderQuality values around existing ImageSource/EditDocument behavior.
- Keep one adjustment model and one deterministic pipeline for every quality.
- Document output extent, color space, and pipeline ordering contracts.

## Acceptance criteria

- [ ] All five quality tiers are represented without duplicate edit models.
- [ ] The rendering API has no SwiftUI/AppKit view dependency.
- [ ] Neutral requests preserve orientation and expected extent.
- [ ] Preview and export differ only through explicit quality/output policy.

## Verification

- Adapt fake renderer and add request contract/parity tests.

## Out of scope

- UI scheduling.
- New image adjustments.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
