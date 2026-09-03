---
id: LUMO-093
title: Rename the Adjust inspector tab to Color
type: task
status: done
priority: medium
labels:
  - mvp
  - ux
  - epic:color
created: 2026-09-01T14:35:36.026Z
updated: 2026-09-01T16:10:43.493Z
order: a0
board: product
commits:
  - 59b3a2e
---

## Objective

Rename the Adjust inspector tab and its user-facing heading to Color so the navigation matches the
actual contents of the panel.

## Context

The `.adjust` inspector case currently presents `ColorInspectorView`, whose content is White Balance,
Color, Mixer, and Color Grading. “Adjust” is vague and no longer describes the surface; the product
language should consistently call this stage Color.

## Acceptance criteria

- [ ] The inspector switcher displays “Color” where it currently displays “Adjust.”
- [ ] User-facing titles, accessibility labels, help text, and any menu/shortcut references use
  Color consistently for this inspector.
- [ ] Internal enum/state compatibility and persisted edit documents are preserved; this is a UI
  naming change, not a data migration.
- [ ] Add or update coverage for tab titles and routing so selecting Color still presents the
  existing `ColorInspectorView`.

## Implementation notes

Relevant code: `AppViewModel.InspectorTab`, `InfoInspectorView.swift`,
`ColorInspectorView.swift`, and tests that refer to `.adjust` or its display title. Keep internal
case names only if changing them would create unnecessary persistence/API churn.

### Comment — codex @ 2026-09-01T16:07:54.426Z

Implemented and committed as 59b3a2e. The inspector now presents the compatibility-preserved .adjust tab as Color, with Color help/accessibility text and an explicit .adjust-to-ColorInspectorView routing mapping. Added coverage for the Color title, stable raw value, and routing content. Verification: swift test — 510 passed, 26 expected skips; swift test --filter AdjustInspectorTests — 17 passed; swift build -c release — passed; git diff --check — passed; dg validate — OK with the pre-existing unknown pickup-runner model warning.

### Comment — claude @ 2026-09-01T16:10:40.712Z

Verification report (independent counterpoint review)

Reviewed commit 59b3a2e against the acceptance criteria and re-ran checks.

Findings:
- InspectorTab.title now returns "Color" for .adjust; rawValue "adjust" and case name preserved for persistence compatibility (no migration needed) — meets AC3.
- New InspectorTab.Content enum + .content property route .adjust -> .color -> ColorInspectorView in InfoInspectorView.swift; localized, doesn't leak the rename into persisted state.
- accessibilityLabel/accessibilityHint/help text on the tab switcher derive from tab.title/purpose/helpText, so they pick up "Color" automatically — no separate strings were missed.
- purpose text already read "Color adjustments" pre-change; no other "Adjust"-labeled UI strings, menu items, or keyboard shortcuts reference this tab (grepped MenuCommands.swift and all Views/ViewModels — no hits tied to InspectorTab).
- Test coverage added: rawValue stability, title == "Color", content == .color, plus existing routing/ordering tests — satisfies AC4.

Checks re-run independently:
- swift build: passed
- swift test --filter AdjustInspectorTests: 17 passed
- swift test (full suite): 510 passed, 26 expected skips, 0 failures
- git diff --check: clean
- dg validate: OK (pre-existing unrelated pickup-runner model warning only)

Note (non-blocking, out of scope): the working tree has pre-existing uncommitted changes to ColorGradingAdjustments.swift, AppViewModel+Color.swift, ColorInspectorView.swift, and related tests that predate this issue's commit and are unrelated to the tab-rename change. Not touched by 59b3a2e; flagged for visibility only, not a defect in this issue's work.

Verdict: PASS. No blockers, no localized fixes needed, no child tickets required.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T16:10:43.491Z: Independent verification passed: rename confirmed complete (title, a11y, help text, tests), full suite green, no blockers.
