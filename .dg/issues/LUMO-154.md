---
id: LUMO-154
title: Add real view-rendering snapshot/UI coverage for LookInspectorView empty-state matrix
type: task
status: done
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-03T03:57:40.347Z
updated: 2026-09-03T05:40:55.456Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run:
    - swift test --filter LookInspectorViewTests — 4 passed
    - swift test — 695 executed, 14 skipped, 0 failures
    - swift build -c release — passed
    - git diff --check ec52625~1 ec52625 — passed
    - dg validate — OK with pre-existing pickup-model warning
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-03T05:40:55.453Z
  session: 01MTL3FOBX08OLKZQ1
---

Parent: LUMO-144 (verification finding, non-blocking)

## Context

LUMO-144 (3059ae3) added `LookInspectorEmptyState` with a full presentation matrix (scanning,
folder-unavailable, missing-reference, empty-folder, first-look, populated) and covered it with
`LookInspectorViewTests`, which exercises `LookInspectorEmptyState.resolve(...)` and its copy —
i.e. the state-selection logic and strings, not the actual rendered `LookInspectorView` SwiftUI
tree. The issue's acceptance criteria asked for "view-level snapshot/manual coverage" of the
empty, scanning/error, missing-reference, and populated states.

The implementer's completion comment notes manual CUA visual inspection was unavailable in this
environment (no addressable window for the bare SwiftPM executable), and the project has a
zero-third-party-dependency constraint that rules out typical snapshot-testing libraries.

## Suggested direction

Add lightweight view-level coverage using only Apple frameworks, e.g. rendering
`LookInspectorView` via `NSHostingView`/`ImageRenderer` in a test and asserting on
layout/accessibility properties (frame sizes within the documented 240–360pt width range,
presence of expected accessibility labels/traits per state), rather than pixel snapshots. Not
required to block LUMO-144 — the enum-level presentation matrix already keeps the state/copy
logic from regressing; this closes the gap on catching real SwiftUI layout/clipping regressions
at the documented inspector widths.


### Comment — codex @ 2026-09-03T05:37:33.171Z

Implemented in ec52625. Added Apple-framework view-level coverage that hosts and rasterizes LookInspectorView for first-look, scanning, folder-unavailable, missing-reference, empty-folder, and populated states at 240/280/360pt inspector widths; assertions cover fitting layout, raster output, and the state-derived accessibility labels. Verification: swift test --filter LookInspectorViewTests (4 passed); swift test (695 executed, 14 skipped, 0 failures); swift build -c release passed with pre-existing Core Image deprecation warnings; git diff --check passed; dg validate OK with the existing pickup-model and low-context warnings.

## Agent log

- 2026-09-03T05:40:55.454Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- swift test --filter LookInspectorViewTests — 4 passed
- swift test — 695 executed, 14 skipped, 0 failures
- swift build -c release — passed
- git diff --check ec52625~1 ec52625 — passed
- dg validate — OK with pre-existing pickup-model warning
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTL3FOBX08OLKZQ1
Summary: Verified: Apple-framework view-level rendering coverage for LookInspectorView empty-state matrix is sound, correctly scoped, and passing.
