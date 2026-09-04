---
id: LUMO-166
title: "Audit: prevent termination after failed edit persistence flush"
type: bug
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - bug
  - data-loss
  - persistence
  - audit
created: 2026-09-03T23:28:48.445Z
updated: 2026-09-04T02:20:55.329Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The termination flush reports success, failure, and cancellation distinctly.
      result: pass
      notes: PersistenceFlushResult (.success/.failure(String)/.cancelled) is returned by flushPendingWrites and drainPersistence; failure carries the localized error, cancellation is distinguished from both via explicit Task.isCancelled checks.
    - criterion: The app does not approve termination while dirty snapshots remain after a failed flush.
      result: pass
      notes: "AppDelegate.handleTerminationFlushResult only calls sender.reply(toApplicationShouldTerminate: true) automatically on .success; failed snapshots stay in pendingPersistence (drainPersistence returns without removing on error), verified directly by testFailedTerminationFlushCannotApproveQuitSilently."
    - criterion: Users receive retry and explicit quit-without-saving choices for nonrecoverable failures.
      result: pass
      notes: NSAlert in handleTerminationFlushResult presents Retry Saving / Quit Without Saving / Cancel for both .failure and .cancelled; Retry restarts the flush, Quit Without Saving calls discardPendingWrites() before approving termination, Cancel withholds approval.
    - criterion: Tests cover a failing store during applicationShouldTerminate and verify no data-loss approval occurs silently.
      result: pass
      notes: AppDelegate itself lives in the Lumo executable target and is not @testable, per project layout (CLAUDE.md). EditPersistenceIntegrationTests exercises the exact mechanism AppDelegate calls (flushPendingWrites) with a failing store (testFailedTerminationFlushCannotApproveQuitSilently, testFailedPersistenceRemainsDirtyUntilAForcedRetrySucceeds) and a cancellation path (testCancelledFlushIsReportedDistinctly), asserting the snapshot stays dirty and no success is reported.
  checks_run:
    - swift build
    - swift test --filter EditPersistenceIntegrationTests (10 passed)
    - swift test (725 passed, 14 skipped, 0 failures)
  findings:
    - "Non-blocking race: flushPendingWrites() can report a stale .cancelled result if a concurrent requestPersistenceFlush() cancels and replaces the awaited worker with a new one that finishes (and empties pendingPersistence) before the outer call re-checks state. Fail-closed (produces a false 'cancelled' alert, not a false success), so not a data-loss risk. Filed as LUMO-175 (backlog, verification label, parent LUMO-166, low priority)."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T02:20:55.326Z
  session: 01MTMBLWWZUNOKVJUK
---

## Objective

Prevent application termination from approving a quit while edit persistence is still dirty or has failed.

## Context

`drainPersistence` keeps failed snapshots dirty, but `flushPendingWrites()` returns no success state and `LumoApp` always replies `true` after awaiting it. A disk-full, permission, or store-corruption error during quit can therefore lose edits.

## Acceptance criteria

- [ ] The termination flush reports success, failure, and cancellation distinctly.
- [ ] The app does not approve termination while dirty snapshots remain after a failed flush.
- [ ] Users receive retry and explicit quit-without-saving choices for nonrecoverable failures.
- [ ] Tests cover a failing store during `applicationShouldTerminate` and verify no data-loss approval occurs silently.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-04T02:14:06.361Z

Implemented termination-safe persistence flushing in 1a24953. flushPendingWrites now reports success, failure, and cancellation; failed snapshots remain dirty; AppDelegate only approves termination after success and presents Retry Saving / Quit Without Saving / Cancel on failure or cancellation. Added failing-store and cancellation integration coverage. Verification: swift test — 725 passed, 14 skipped, 0 failures.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T02:20:55.327Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The termination flush reports success, failure, and cancellation distinctly. (pass) — PersistenceFlushResult (.success/.failure(String)/.cancelled) is returned by flushPendingWrites and drainPersistence; failure carries the localized error, cancellation is distinguished from both via explicit Task.isCancelled checks.
- [x] The app does not approve termination while dirty snapshots remain after a failed flush. (pass) — AppDelegate.handleTerminationFlushResult only calls sender.reply(toApplicationShouldTerminate: true) automatically on .success; failed snapshots stay in pendingPersistence (drainPersistence returns without removing on error), verified directly by testFailedTerminationFlushCannotApproveQuitSilently.
- [x] Users receive retry and explicit quit-without-saving choices for nonrecoverable failures. (pass) — NSAlert in handleTerminationFlushResult presents Retry Saving / Quit Without Saving / Cancel for both .failure and .cancelled; Retry restarts the flush, Quit Without Saving calls discardPendingWrites() before approving termination, Cancel withholds approval.
- [x] Tests cover a failing store during applicationShouldTerminate and verify no data-loss approval occurs silently. (pass) — AppDelegate itself lives in the Lumo executable target and is not @testable, per project layout (CLAUDE.md). EditPersistenceIntegrationTests exercises the exact mechanism AppDelegate calls (flushPendingWrites) with a failing store (testFailedTerminationFlushCannotApproveQuitSilently, testFailedPersistenceRemainsDirtyUntilAForcedRetrySucceeds) and a cancellation path (testCancelledFlushIsReportedDistinctly), asserting the snapshot stays dirty and no success is reported.
Checks run:
- swift build
- swift test --filter EditPersistenceIntegrationTests (10 passed)
- swift test (725 passed, 14 skipped, 0 failures)
Findings:
- Non-blocking race: flushPendingWrites() can report a stale .cancelled result if a concurrent requestPersistenceFlush() cancels and replaces the awaited worker with a new one that finishes (and empties pendingPersistence) before the outer call re-checks state. Fail-closed (produces a false 'cancelled' alert, not a false success), so not a data-loss risk. Filed as LUMO-175 (backlog, verification label, parent LUMO-166, low priority).
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTMBLWWZUNOKVJUK
Summary: Verified LUMO-166: flushPendingWrites/drainPersistence report success/failure/cancelled distinctly, AppDelegate only auto-approves termination on success and presents Retry/Quit Without Saving/Cancel otherwise. swift build and full swift test (725 passed, 14 skipped, 0 failures) both clean. One non-blocking race filed as LUMO-175.
