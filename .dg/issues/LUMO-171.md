---
id: LUMO-171
title: "Audit: coalesce and cancel stale Look thumbnail renders"
type: task
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - performance
  - rendering
  - look
  - audit
created: 2026-09-03T23:31:00.000Z
updated: 2026-09-03T23:31:00.000Z
order: zzzza
board: product
---

## Objective

Coalesce and cancel stale Look-thumbnail renders so rapid edits and scrolling do not starve active editor work.

## Context

Look-preview task identity changes with every document revision, but each scheduler request receives a unique job ID. SwiftUI task cancellation does not reliably cancel the queued scheduler job, and each thumbnail takes an encoded-raster round trip before becoming a `CGImage`. Slider dragging can therefore create a render storm of obsolete work.

## Acceptance criteria

- [ ] Newer requests for the same source/Look replace or supersede older queued work.
- [ ] SwiftUI task cancellation propagates through the scheduler to the render operation.
- [ ] Look thumbnails refresh at an intentional edit cadence rather than every transient pointer tick.
- [ ] Preview generation uses a direct image/texture path without unnecessary encode/decode work.
- [ ] Tests or instrumentation demonstrate bounded stale work while dragging and scrolling.

## Implementation notes

Coordinate with LUMO-165 so cancellation and eviction have one terminal-result contract. Preserve latest-wins behavior for source and document generations.
