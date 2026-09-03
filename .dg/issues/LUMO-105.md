---
id: LUMO-105
title: Export format selection does not persist across export dialogs
type: task
status: done
priority: low
labels:
  - verification
created: 2026-09-01T19:32:47.463Z
updated: 2026-09-01T21:23:26.125Z
depends_on:
  - LUMO-095
order: w
board: product
commits:
  - 724ad99
---

## Objective

Restore export-format stickiness that the LUMO-095 toolbar removal (b38d394) dropped.

## Context

Before LUMO-095, `ExportCoordinator.format` was a `@Published` property, so a format chosen once
(TIFF, say, for a batch export) stayed selected for the rest of the session across subsequent
export dialogs. After b38d394 moved the format control into an `NSSavePanel`/`NSOpenPanel`
accessory view (`ExportFormatAccessoryView`), each `exportDialog`/`batchExportDialog` call
constructs a fresh accessory seeded from `ExportCoordinator.defaultFormat` (hardcoded `.jpeg`) —
see `Sources/LumoKit/ViewModels/ExportCoordinator.swift` around `exportDialog`/`batchExportDialog`.
A user who exports a TIFF and then exports again will see JPEG pre-selected rather than their last
choice.

Found during independent verification of LUMO-095 (b38d394); not a blocker for that issue (its
acceptance criteria didn't require stickiness and the pre-existing default was already `.jpeg`),
but it's a real, user-visible behavior change worth fixing deliberately.

## Acceptance criteria

- [ ] The format selected in the export/batch-export accessory view is remembered and pre-selected
  the next time either dialog is opened in the same session.
- [ ] Add/update coverage for the persisted-selection behavior.

## Implementation notes

Likely a small `ExportCoordinator`-owned `lastUsedFormat` (or similar) that `exportDialog` and
`batchExportDialog` seed `ExportFormatAccessoryView` from instead of the hardcoded
`Self.defaultFormat`, updated when the dialog completes.

Parent: LUMO-095


### Comment — codex @ 2026-09-01T21:20:07.030Z

Implemented and committed as 724ad99. ExportCoordinator now owns a session-scoped lastUsedFormat, seeds both single and batch export accessories from it, records the selected format when export begins/dialog completes, and preserves JPEG as the fresh-session default. Added ExportCoordinatorTests coverage across single and batch exports. Verification: swift test (561 passed, 26 expected skips, 0 failures), swift test --filter ExportCoordinatorTests (13 passed), swift build -c release passed, git diff --check passed, dg validate passed with the known pickup-runner model warning.


### Comment — claude @ 2026-09-01T21:23:23.336Z

### Independent verification report (counterpoint agent)

**Result: PASS**

Reviewed commit 724ad99 against both acceptance criteria and Swift 6 constraints.

- `ExportCoordinator.lastUsedFormat` is a private(set), @MainActor, non-Published var
  initialized to `.jpeg` (Self.defaultFormat), matching "preserves JPEG as the fresh-session
  default" and avoiding an unneeded UI-refresh publish.
- `exportDialog` and `batchExportDialog` both seed `ExportFormatAccessoryView` from
  `lastUsedFormat` instead of the hardcoded default — satisfies criterion 1 (format is
  pre-selected next time either dialog opens in the same session).
- `lastUsedFormat` is updated at the point each export actually starts
  (`performExport`, `performBatchExport`), plus once more in `batchExportDialog` right after
  the panel closes (comment explains why: to seed a fast second batch dialog before the async
  task finishes). Redundant but harmless — not a bug.
- If a panel is cancelled (`runModal() != .OK`), `lastUsedFormat` is correctly left untouched,
  since no export occurred.
- Session-scoped only (no UserDefaults persistence) — correct per the issue's explicit scope
  ("within the same session"); not a gap.
- Test coverage: `testLastUsedFormatPersistsAcrossSingleAndBatchExports` in
  `ExportCoordinatorTests.swift` exercises persistence across a single export → batch export →
  fresh-coordinator-defaults-to-jpeg sequence. Satisfies criterion 2.

No correctness, maintainability, security, or performance issues found. No new public API,
schema, or migration introduced — pure internal state on an existing @MainActor class.

**Checks run (this pass, independent of the implementer's report):**
- `swift test` — 561 passed, 26 expected skips, 0 failures
- `swift test --filter ExportCoordinatorTests` — 13 passed, 0 failures
- `swift build -c release` — clean build

No blocker. No follow-up tickets needed. Clearing claim and moving to done.

## Agent log

- 2026-09-01T21:23:26.124Z: Independent verification passed: lastUsedFormat correctly persists export format selection across single/batch export dialogs within a session; full test suite, filtered tests, and release build all green.
