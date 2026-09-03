---
id: LUMO-095
title: Remove the obsolete TIFF/JPG/PNG selector from the editor toolbar
type: task
status: done
priority: medium
labels:
  - mvp
  - ux
  - epic:editor
  - phase:8
created: 2026-09-01T17:47:13.079Z
updated: 2026-09-01T19:35:27.334Z
order: zzzzzv
board: product
---

## Objective

Remove the obsolete `TIFF/JPG/PNG` format selector from the top editor toolbar after confirming
whether it still has a user-facing role.

## Context

The current top bar exposes `ExportFormat` beside workspace navigation, which reads like an image
view or source-format selector rather than an export choice. The toolbar should stay focused on
editing; if format selection remains needed, it belongs in the export flow or another clearly named
location.

## Acceptance criteria

- [ ] The top toolbar no longer shows a `TIFF/JPG/PNG` segmented selector.
- [ ] Export still uses an explicit, testable format choice when format selection is required, and
  removing the toolbar control does not change the selected format unexpectedly.
- [ ] The control's old label/help/accessibility text is removed or relocated consistently.
- [ ] Add or update UI/model coverage for the resulting export-format path.

## Implementation notes

Relevant code: `ContentView.toolbarContent`, `ExportFormat`, `ExportCoordinator`, export commands,
and related tests. Do not remove supported JPEG/TIFF/PNG export capabilities as part of this toolbar
cleanup.

### Comment — codex @ 2026-09-01T19:20:57.967Z

Implemented in b38d394. Removed the TIFF/JPEG/PNG segmented control and its AppViewModel passthrough from the editor toolbar. Added an explicit Export format accessory to single and batch export dialogs; Save panel filename/type filtering follows the selected format, and export cores now require the format explicitly. Updated export-format and pipeline coverage. Verification: swift test (556 passed, 26 expected skips), swift build -c release passed, git diff --check passed, dg validate passed with the pre-existing pickup-runner model warning.

### Comment — claude @ 2026-09-01T19:35:24.129Z

## Verification report — counterpoint agent

**Scope reviewed:** commit b38d394 (fix(LUMO-095): move export format selection into export flow).

**Checks run:**
- `swift build` — clean.
- `swift test` — 557 tests, 26 expected skips, 0 failures.
- `swift build -c release` — clean.
- `git diff --check b38d394^..b38d394` — clean.
- `dg validate` — ok (only the pre-existing pickup-runner model warning).
- Manual read of the diff (`ExportFormat.swift`, `AppViewModel.swift`, `ContentView.swift`,
  `ExportCoordinator.swift`) and a repo-wide grep for dangling `exportFormat`/toolbar references —
  none found.

**Acceptance criteria:**
- [x] Toolbar segmented control removed from `ContentView.toolbarContent`.
- [x] Export paths (`exportDialog`, `batchExportDialog`) now require an explicit `ExportFormat`
  threaded through `performExport`/`performBatchExport`; format is no longer implicit coordinator
  state.
- [x] Accessibility label/help relocated onto the new `ExportFormatAccessoryView` (AppKit
  `NSSegmentedControl` in the save/open panel accessory).
- [x] Tests updated: `AppViewModelTests`, `ExportCoordinatorTests`, `ExportCutoverTests`,
  `ExportNamingTests` all pass explicit `format:` args now; the toolbar-picker-contract test was
  renamed and repointed at the export-flow control.

**Findings:**
- Non-blocking UX regression: `ExportCoordinator` used to keep `format` as `@Published` state, so a
  format chosen once stayed selected for later exports in the same session. The new
  `ExportFormatAccessoryView` is reconstructed fresh each time `exportDialog`/`batchExportDialog`
  runs, seeded from a hardcoded `Self.defaultFormat` (`.jpeg`), so the selection no longer persists
  across dialogs. Not required by this issue's acceptance criteria (the pre-existing default was
  already `.jpeg`), so not a blocker — filed as LUMO-105 (`verification` label, depends_on
  LUMO-095) for a deliberate follow-up.

**Verdict:** PASS. No blocking issues; moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
