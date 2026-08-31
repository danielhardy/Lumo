---
id: LUMO-062
title: Relink status can silently mask a prior actionable edit-store status
type: task
status: done
priority: low
labels:
  - verification
created: 2026-08-31T03:40:18.521Z
updated: 2026-08-31T04:12:07.668Z
order: a0
board: product
commits:
  - 58803f0
---

## Objective

Clarify/fix the status precedence in `EditDocumentStore.load(for:)`'s relink path so a prior actionable status (e.g. `.recoveredFromBackup`, `.migrated`) isn't silently dropped in favor of `.relinked`, or vice versa.

## Context

Found during LUMO-008 verification (non-blocking). In `Sources/LumoKit/Models/EditDocumentStore.swift:157-166`:

```swift
let previousStatus = status
status = .relinked
do {
    try persist()
} catch {
    status = .writeFailure(error.localizedDescription)
}
if previousStatus.isActionable, case .writeFailure = status {} else if previousStatus.isActionable {
    status = previousStatus
}
```

If the store just recovered from backup or migrated on load (`previousStatus.isActionable == true`) and then a relink also happens on the same load, the relink silently reverts `status` back to the *previous* actionable status — the user never sees the "Restored edits after the source photo moved" message, only the earlier one. It's a real but narrow edge case (backup-recovery/migration and a moved source coinciding), and produces no data loss — only a suppressed status message — so it's not blocking LUMO-008.

## Scope

- Decide the intended precedence (likely: report whichever event is more actionable to the user, or concatenate messages) and make the code do that explicitly rather than via the current double-conditional.
- Add a test that recovers from backup (or migrates) and relinks in the same `load()` call, asserting the final status/message.

## Out of scope

- Any change to the write-path atomicity or recovery guarantees themselves.


### Comment — codex @ 2026-08-31T04:08:49.511Z

Implemented in 486b687. EditDocumentStore now explicitly combines multiple actionable load events in chronological order, preserving recovery/migration, relink, and write-failure messages instead of silently replacing one with another. Added backup-recovery-plus-relink regression coverage. Verification: swift test passed (326 tests, 20 skipped), swift build -c release passed, git diff --check passed, and dg validate passed.


### Comment — claude @ 2026-08-31T04:12:03.286Z

## Verification report (independent counterpoint review)

**Verdict: pass, with one fix applied.**

Reviewed 486b687 (Preserve edit-store events during relink) against the issue scope.

Checks run:
- `swift build` — clean
- `swift test` — 327 tests, 20 skipped, 0 failures (up from 326 after adding a regression test)
- `swift build -c release` — clean
- `git diff --check` — clean
- `dg validate` — OK (pre-existing unrelated warnings only)

Findings:
- The `Status.combining` precedence logic and `EditDocumentStore.load(for:)` correctly report both a prior actionable status (recovery/migration) and a subsequent relink, per the issue's ask. The added `testBackupRecoveryAndRelinkReportBothActionableEvents` covers the scenario described in the issue.
- **Bug found and fixed (commit 58803f0):** `status` is actor instance state that survives across separate `load(for:)` calls. Because `combining` didn't dedupe, relinking a second photo right after a first relink in the same session combined the leftover `.relinked` status with the new one, producing a doubled message: "Restored edits after the source photo moved. Restored edits after the source photo moved." This is worse than pre-fix behavior (which showed the message once). Fixed by deduplicating identical statuses in `Status.combining` before wrapping them in `.combined`. Added `testSecondRelinkOnTheSameStoreDoesNotDuplicateTheMessage` regression coverage.
- No other call sites switch exhaustively on `EditDocumentStore.Status`; `AppViewModel` only reads `.isActionable`/`.message`, both of which already handle `.combined` correctly.

No blockers remain. Verification commit: 58803f0.

## Agent log

- 2026-08-31T04:12:07.666Z: Verified LUMO-062: relink status precedence fix (486b687) is correct and tested; found and fixed a regression where sequential relinks in one session duplicated the status message (58803f0). All checks pass.
