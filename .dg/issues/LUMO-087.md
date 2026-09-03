---
id: LUMO-087
title: Remove the legacy Other Adjustments section from the Color inspector
type: task
status: done
priority: medium
labels:
  - mvp
  - ux
  - epic:color
created: 2026-09-01T14:35:34.258Z
updated: 2026-09-01T15:53:37.390Z
order: zzzzy
board: product
---

## Objective

Remove the user-facing legacy “Other Adjustments” accordion from the Color inspector.

## Context

`ColorInspectorView` currently renders an `Other Adjustments` disclosure section for older ordered
adjustment-node controls that are not part of the photographer-facing Color surface. It makes the
Color panel look unfinished and duplicates concepts that should either be represented by named
Color controls or remain an internal compatibility path.

## Acceptance criteria

- [ ] The Color inspector no longer shows an “Other Adjustments” title, accordion, or its duplicate
  controls in the normal UI.
- [ ] Existing saved documents still decode and render their legacy adjustment nodes correctly;
  removing the section does not delete or silently reset persisted values.
- [ ] Reset, undo, preview, and export behavior for supported Color controls remains unchanged.
- [ ] Add or update UI/state coverage and a legacy-document regression check for hidden-but-preserved
  adjustment data.

## Implementation notes

Relevant code: `Sources/LumoKit/Views/ColorInspectorView.swift`, `AdjustInspectorView.swift`,
`AppViewModel+Adjust.swift`, and `EditDocument`/render compatibility paths. Separate UI removal
from model migration unless a migration is explicitly required.

### Comment — codex @ 2026-09-01T15:51:58.526Z

Implemented in commit f2d9ede. Removed the legacy “Other Adjustments” disclosure, state, and duplicate controls from ColorInspectorView while leaving AdjustmentNode persistence/render compatibility and AdjustInspectorView intact. Added ColorInspectorTests coverage proving supported Color resets preserve all legacy ordered adjustment nodes, plus EditDocumentTests coverage proving a legacy payload with absent new Color fields decodes and round-trips those nodes unchanged. Verification: swift test — 508 passed, 26 expected fixture skips; swift build -c release — passed; git diff --check — passed; dg validate — OK with the pre-existing unknown pickup-runner model warning.

### Comment — claude @ 2026-09-01T15:53:35.280Z

## Verification report — counterpoint review

**Verdict: PASS**

Reviewed commit f2d9ede against the acceptance criteria and current tree.

- Build: `swift build` — clean, no warnings.
- Tests: `swift test` — 508 passed, 26 expected fixture skips, 0 failures.
- No dead code: `otherAdjustmentsExpanded`/`otherAdjustmentsSection` fully removed; grepped for
  residual references — none. `visibleAdjustmentControls`, `adjustmentBinding(for:)`, and
  `resetAdjustment(_:)` remain in use (legitimately) by `AdjustInspectorView`, which stays the
  single home for `AdjustmentControl` rows — no duplicate UI reintroduced.
- Persistence/compat: `AdjustmentNode` model, decoding, and render compatibility paths untouched;
  `EditDocumentTests.testLegacyDocumentKeepsAdjustmentNodesWhenNewColorFieldsAreAbsent` proves a
  legacy payload with absent Color fields decodes and round-trips its adjustment nodes unchanged.
- Reset behavior: `ColorInspectorTests.testColorResetsPreserveLegacyAdjustmentNodes` proves
  resetting Mixer/Grading/Color state does not touch legacy ordered adjustment nodes.
- Acceptance criteria: all four items satisfied (UI removed; legacy docs preserved; reset behavior
  unchanged and covered; new UI/state + legacy-document regression tests added).

No blocking issues found. No backlog child tickets warranted — the removal is self-contained and
the compatibility path is explicitly out of scope per the issue's implementation notes.

Note: the working tree has unrelated uncommitted changes (a color-grading wheel control in
ColorInspectorView.swift/AppViewModel+Color.swift/ColorGradingAdjustments.swift) that predate this
verification session and are untouched by it — flagging for visibility, not a finding against
LUMO-087.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
