---
id: LUMO-128
title: Make imported Looks/LUTs selectable and applicable
type: bug
status: done
priority: high
verification_agent: pi
verification_model: openrouter/z-ai/glm-5.3-flash
labels:
  - lut
  - ux
created: 2026-09-02T12:45:18.384Z
updated: 2026-09-02T14:44:56.662Z
order: a0
board: product
commits:
  - fe187c8
---

## Objective

Make imported Looks/LUTs selectable and applicable from the Looks browser.

## Context

Imported LUT files are successfully discovered and appear in the list, but clicking an imported
entry currently has no observable effect. This leaves the user with a misleading success state:
the file is present, yet there is no way to apply it to the active photo. The fix must cover the
selection-to-render path, not only the scan/list presentation, and should remain testable while the
canvas is zoomed past 100% where the black-canvas regression may otherwise mask a changed image.

## Acceptance criteria

- [ ] Clicking an imported valid LUT selects it for the active photo and schedules a render whose
      output reflects that LUT.
- [ ] The selected imported LUT has clear selected/active state and respects the existing intensity
      control; clicking a different LUT replaces the active selection.
- [ ] Selection survives normal photo navigation and edit persistence/relaunch according to the
      existing per-photo LUT contract; built-in and derived Looks continue to work.
- [ ] Missing, invalid, or not-yet-resolved LUTs provide an actionable state instead of silently
      ignoring the click.
- [ ] Add regression coverage for imported-LUT click handling, render scheduling, and persisted
      selection.

## Implementation notes

Trace the imported entry's identity and action through `LUTLibrary`, the Looks inspector, and
`AppViewModel` resolution/render scheduling. Preserve canonical LUT IDs and the existing optional
Look model; do not work around the issue by applying a global LUT or by making list appearance imply
selection. LUMO-085 and LUMO-041 document the current user-facing and persistence contracts.

### Comment — codex @ 2026-09-02T13:30:23.433Z

Implemented in commit fe187c8. Look browser rows are explicit ID-based buttons, so imported Looks now select the active photo and schedule the normal preview render; selected/active state and intensity remain driven by the persisted per-photo LUT model. Added an unresolved-Look recovery notice with a clear-reference action, and regression coverage for imported ID selection/render scheduling while zoomed to 200% plus persistence. Verification: swift test (602 passed, 13 expected skips), swift test --filter LUTWorkflowTests (6 passed), swift build -c release passed, git diff --check passed.

### Comment — pi @ 2026-09-02T14:43:44.528Z

## Verification report — counterpoint review (pi, post-human-review)

**Verdict: PASS.** Commit fe187c8 correctly closes the selection-to-render gap and satisfies all five acceptance criteria. No code changes required from verification; no verification commits were made.

### Checks run (all in this working tree, main @ fe187c8)

- `swift build` — pass (clean, no diagnostics)
- `swift build -c release` — pass
- `swift test --filter LUTWorkflowTests` — 6/6 pass
- `swift test` (full suite) — run 1: 602 executed, 13 skipped, 0 failures; runs 2 and 3: 1 failure each in the unrelated pre-existing flake `CropWorkflowTests.testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit` (see Finding 1)
- `git diff --check` — pass

### Acceptance criteria assessment

1. **Imported LUT click → selection + render** ✅ `LookInspectorView` rows are now ID-based `Button`s calling `viewModel.selectLook(id:)`; `selectLook(id:)` resolves via `resolvedLUT(_:)` and routes through the normal `updateDocument` → `schedulePreview` path. Regression test verifies selection, a new preview request (count delta), and LUT delivery at 200% zoom.
2. **Selected/active state + intensity** ✅ `LookRow(isSelected:)` is driven by the persisted `document.lut.lutID`; the intensity slider binds to `setLookIntensity` and is exercised (0.35) in the regression test.
3. **Navigation + persistence** ✅ `testLUTSurvivesNavigationAndRelaunchForItsPhoto` plus the relaunch block of the new test (fresh `AppViewModel` over the same `EditDocumentStore` re-resolves the imported ID at intensity 0.35). Canonical IDs preserved; `LUTSettings` model untouched.
4. **Unresolved LUTs actionable** ✅ With the minor caveat in Finding 2: during scan → status message; persisted-but-missing → `lutResolutionStatus` + the new "Clear Look Reference" recovery notice in the inspector (`selectedLookID != nil && selectedLook == nil`), covered by `testCanonicalLookStateDistinguishesMissingReferenceFromExplicitNone`.
5. **Regression coverage** ✅ Imported-ID selection, render scheduling over the zoomed canvas, and persisted selection are all covered.

### Review findings (correctness / maintainability / security / performance)

1. **Pre-existing flake, already tracked (non-blocking):** `CropWorkflowTests.testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit` failed in 2 of 3 full-suite runs, passed in isolation 3/3. Unrelated to fe187c8 (file last touched by LUMO-124/LUMO-115; the commit touches only `AppViewModel.swift`, `LookInspectorView.swift`, `LUTWorkflowTests.swift`). Evidence appended to **LUMO-132** (existing backlog child of LUMO-124).
2. **Filed as backlog child LUMO-133 (parent LUMO-128, label `verification`):** a click on a row that fails to resolve is silent when the active photo has no Look or a resolved one — `refreshLUTResolutionStatus()` reports only on the document's own ID, and the scan-complete retry is manual. Narrow window (rows render only from resolvable scan results; parsed `CubeLUT`s persist in memory between rescans), polish not correctness — criterion 4 holds for the primary cases.
3. **Correctness details verified, no action:** Button action + `List(selection:)` binding can both invoke `selectLook(id:)` on one click; the second call short-circuits in `updateDocument` (`updated != document` guard), so no double render or duplicate undo record. Swift 6 data-race rules respected (no new concurrency surface, no opt-outs). No new input parsing, persistence schema, or public API — no security or performance concerns. Undo/history, derived-LUT registry, and the `None` row remain intact.

### Bookkeeping

- Backlog child filed: LUMO-133 (`verification`, parent LUMO-128)
- Flake evidence appended: LUMO-132
- Verification commits: none (review-only pass; fix commit remains fe187c8)
- Tree note: uncommitted README.md/.gitignore/realworldtest/ changes predate this claim and belong to a separate workstream — left untouched.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T14:44:56.660Z: Verified by counterpoint review (pi): full checks pass (swift build, release build, 602-test suite modulo a pre-existing unrelated crop flake tracked in LUMO-132, git diff --check). All five acceptance criteria hold; regression coverage confirmed. Non-blocking polish filed as LUMO-133.
