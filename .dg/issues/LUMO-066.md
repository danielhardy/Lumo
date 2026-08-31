---
id: LUMO-066
title: Remove or use LightAdjustments.existingNodeRepresentation
type: task
status: backlog
priority: low
labels:
  - verification
created: 2026-08-31T19:36:45.652Z
updated: 2026-08-31T19:36:51.802Z
order: zzy
board: product
---

Parent: LUMO-025 (verification finding, non-blocking)

## Context

LUMO-025 replaced `LightAdjustments.existingNodeRepresentation`-based rendering with a native
EV + `CIToneCurve` implementation in `RenderPipeline.applyLight` (commit 64a8f01). The
`existingNodeRepresentation` computed property in `Sources/LumoKit/Models/LightAdjustments.swift`
was kept, with a doc comment claiming it "remains available for migration/diagnostic code."

A repo-wide grep at verification time (2026-08-31) found zero callers — no production code,
no test references it.

## Scope

- Either delete `existingNodeRepresentation` (and its private `AdjustmentNode` construction
  helpers if they become unused too), or add a real caller/test that exercises it if it is
  actually needed for a migration path.
- Out of scope for this ticket: any change to `RenderPipeline.applyLight` behavior.

## Why non-blocking

Dead code, not a correctness or safety issue. Left as a backlog cleanup rather than folded into
LUMO-025's verification fix to keep that fix minimal and localized.
