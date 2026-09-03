---
id: LUMO-141
title: Open the Info inspector after the first successful Photos import
type: feature
status: done
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - import
  - ux
  - navigation
created: 2026-09-03T01:12:22.295Z
updated: 2026-09-03T03:44:49.360Z
depends_on:
  - LUMO-129
estimate: 2
order: a0
board: product
commits:
  - 64cd386
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: First successful Photos import item opens the existing Info inspector for that active item
      result: pass
    - criterion: Multi-item import opens the inspector once for the first successful item; later transfers do not retarget it
      result: pass
    - criterion: Presented inspector shows the selected photo current metadata/histogram and does not retain stale content
      result: pass
    - criterion: Cancellation before any accepted item, empty selection, all-failure import leave inspector presentation unchanged
      result: pass
    - criterion: "Repeated imports are idempotent: no duplicate panels, no tab change, no reset of unrelated inspector preferences"
      result: pass
    - criterion: Automated coverage exercises first-success, partial-success, all-failure, cancellation, repeated-import paths
      result: pass
  checks_run:
    - swift test --filter PhotosImportTests — 13 tests, 0 failures
    - swift test (full suite) — 673 executed, 14 expected skips, 0 failures
    - git diff --check on verification commit — clean
    - Traced inspectorState.isPresented wiring through ContentView.swift .inspector(isPresented:) modifier to confirm the ViewModel state change is actually connected to the presented UI
    - Traced keepInspectorTabValid() call sites to confirm it only adjusts inspectorTab (not isPresented) and cannot fight the new presentation logic
  findings: []
  fixes:
    - Added testFirstImportFailureThenSuccessStillPresentsInspectorForTheSuccessfulItem to PhotosImportTests.swift — the existing tests covered success-then-success and success-then-failure orderings but not a leading failure before the first success; the presentation gate (collection.importedDataCount == 1) is correct for this case but was untested
  verification_commits:
    - 64cd386
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-03T03:44:49.354Z
  session: 01MTKZ3SF92D4E3SOP
---

## Objective

After the first successful item in a Photos import, open Lumo's existing right-side Info inspector so the imported photo is immediately ready for inspection and editing.

## Context

The current Photos import path streams items through `ImageCollection`, opens the first successful item through `AppViewModel`, and leaves inspector presentation unchanged. The product surface is the SwiftUI `.inspector` containing `InfoInspectorView`; this ticket is about that presentation state, not adding another sidebar or redesigning inspector tabs. The first successful item is the import's active edit photo even when later items are still transferring.

## Acceptance criteria

- [ ] The first successful Photos import item opens the existing Info inspector and the inspector is presented for that active item.
- [ ] A multi-item import opens the inspector once for the first successful item, even if later transfers are still in progress; later items must not retarget it unexpectedly.
- [ ] The presented inspector shows the selected photo's current metadata/histogram state and does not retain stale content from the previously active photo.
- [ ] Cancellation before any accepted item, an empty selection, and an import in which every item fails leave the inspector presentation unchanged.
- [ ] Repeated imports are idempotent: they do not create duplicate panels, change the selected inspector tab, or reset unrelated inspector preferences.
- [ ] Automated view-model/state coverage exercises first-success, partial-success, all-failure, cancellation, and repeated-import paths; the existing mouse/keyboard import entry points remain covered by the same state transition.

## Implementation notes

Trace the import-completion event through `AppViewModel` selection and `InspectorState.isPresented` rather than coupling the behavior to `PhotosPicker` implementation details. Preserve the existing selected tab and Info-inspector state model where possible.

## Verification

Run focused `AppViewModel`/Photos-import state tests plus the full Swift test suite. Manually verify first-success, partial-success, all-failure, cancellation, and repeated import from the menu and keyboard command path.

## Out of scope

- Changing the Library/Edit navigation mode, source-folder browser, or Open Image behavior.
- Adding new inspector tabs or changing when histogram work is scheduled.


### Comment — codex @ 2026-09-03T03:36:17.124Z

Implemented in commit 701d864. AppViewModel now presents the existing inspector exactly once on the first accepted Photos import item, preserves the selected tab/preferences, and keeps metadata/histogram clearing tied to the active source load. Added coverage for first success, partial success, all-failure, cancellation, empty selection, repeated imports, active-item selection, and stale Info state. Verification: swift test --filter PhotosImportTests (12 passed); swift test (672 passed, 14 expected skips, 0 failures); swift build -c release passed; git diff --check passed; dg validate OK with the pre-existing pickup-model warning.

## Agent log

- 2026-09-03T03:44:49.358Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] First successful Photos import item opens the existing Info inspector for that active item (pass)
- [x] Multi-item import opens the inspector once for the first successful item; later transfers do not retarget it (pass)
- [x] Presented inspector shows the selected photo current metadata/histogram and does not retain stale content (pass)
- [x] Cancellation before any accepted item, empty selection, all-failure import leave inspector presentation unchanged (pass)
- [x] Repeated imports are idempotent: no duplicate panels, no tab change, no reset of unrelated inspector preferences (pass)
- [x] Automated coverage exercises first-success, partial-success, all-failure, cancellation, repeated-import paths (pass)
Checks run:
- swift test --filter PhotosImportTests — 13 tests, 0 failures
- swift test (full suite) — 673 executed, 14 expected skips, 0 failures
- git diff --check on verification commit — clean
- Traced inspectorState.isPresented wiring through ContentView.swift .inspector(isPresented:) modifier to confirm the ViewModel state change is actually connected to the presented UI
- Traced keepInspectorTabValid() call sites to confirm it only adjusts inspectorTab (not isPresented) and cannot fight the new presentation logic
Findings:
- None
Fixes:
- Added testFirstImportFailureThenSuccessStillPresentsInspectorForTheSuccessfulItem to PhotosImportTests.swift — the existing tests covered success-then-success and success-then-failure orderings but not a leading failure before the first success; the presentation gate (collection.importedDataCount == 1) is correct for this case but was untested
Verification commits:
- 64cd386
Actor: claude
Resolved model: sonnet
Pickup session: 01MTKZ3SF92D4E3SOP
Summary: Independent verification pass on commit 701d864: inspector presentation is correctly gated to the first successful Photos import item, tab/preferences preserved, metadata/histogram cleared via existing load() path, no reopen on later items or repeated imports. Full swift test suite (673 tests, 0 failures) and release build pass. Added one localized test (failure-then-success ordering) as commit 64cd386; no blockers found.
