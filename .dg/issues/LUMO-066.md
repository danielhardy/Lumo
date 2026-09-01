---
id: LUMO-066
title: Remove or use LightAdjustments.existingNodeRepresentation
type: task
status: done
priority: low
labels:
  - verification
created: 2026-08-31T19:36:45.652Z
updated: 2026-08-31T20:15:54.799Z
order: zzv
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


### Comment — codex @ 2026-08-31T20:15:04.150Z

Implemented and committed as fcc57cb: removed the unused LightAdjustments.existingNodeRepresentation compatibility property and corrected its enclosing documentation. Verified with swift test: 380 executed, 20 skipped, 0 failures.


### Comment — claude @ 2026-08-31T20:15:52.871Z

## Verification report — counterpoint agent (2026-08-31)

**Result: PASS**

Checked commit fcc57cb against the ticket scope:
- `LightAdjustments.existingNodeRepresentation` and its `AdjustmentNode`-construction body
  are fully deleted from `Sources/LumoKit/Models/LightAdjustments.swift`; the surrounding
  doc comment was correctly reworded (no more claim that it's used for "migration/diagnostic
  code").
- Repo-wide grep for `existingNodeRepresentation` after the commit: zero hits (source and
  tests). No orphaned private helpers left behind — the deleted property was self-contained.
- Remaining `AdjustmentNode` references in the tree are the unrelated, still-live general
  adjustment-node enum used throughout `RenderPipeline`/`AdjustInspectorView`/tests — not in
  scope and untouched, consistent with the ticket's "out of scope: `applyLight` behavior."
- `swift build`: clean.
- `swift test`: 380 executed, 20 skipped, 0 failures — matches the implementer's reported
  numbers exactly.
- `git status --porcelain`: no unexpected tracked-source changes from this verification pass.

No blockers, no follow-up child tickets needed — this was a pure dead-code deletion matching
the ticket's stated scope with no behavior change.
