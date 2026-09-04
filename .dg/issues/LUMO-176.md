---
id: LUMO-176
title: Verify EditPersistenceCoordinator flush() cancelled+empty-pending success mapping is intentional and covered
type: task
status: done
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - maintainability
  - persistence
created: 2026-09-04T03:02:22.104Z
updated: 2026-09-04T13:00:56.979Z
parent: LUMO-168
depends_on:
  - LUMO-168
order: a0
board: product
commits:
  - 94569ae
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Confirm with the author/PR history whether this branch was deliberate, or file it as a recognized fix
      result: pass
    - criterion: Add a regression test that drives the worker into returning .cancelled with pending empty and asserts flush() returns .success
      result: pass
    - criterion: No production code change expected unless the behavior turns out to be unintentional
      result: pass
  checks_run:
    - swift test --filter EditPersistenceIntegrationTests — 11 executed, 0 failures
    - "Mutation check: removed the `if result == .cancelled, pending.isEmpty { return .success }` line in EditPersistenceCoordinator.swift and re-ran testRacedFlushReportsSuccessAfterReplacementDrainsQueue — it failed (cancelled vs success) as expected, confirming the new test detects the regression; change reverted, tree left clean"
    - scripts/check-swift-format.sh — no violations in EditDocumentStore.swift, EditPersistenceCoordinator.swift, or EditPersistenceIntegrationTests.swift (remaining reported violations are pre-existing, in unrelated in-progress ImageCollection.swift)
    - git status --porcelain on touched files — clean, no stray edits from review
  findings: []
  fixes: []
  verification_commits:
    - 94569ae
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T13:00:56.976Z
  session: 01MTMYFCEMPKAMZUP0
---

## Objective

Verify EditPersistenceCoordinator flush() cancelled+empty-pending success mapping is intentional and covered

## Context

Counterpoint verification of LUMO-168 (commit `8fd2ff9`) found that the mechanical extraction of
`AppViewModel`'s persistence policy into `EditPersistenceCoordinator.flush()`
(`Sources/LumoKit/ViewModels/EditPersistenceCoordinator.swift:121-138`) introduced one line of new
behavior that was not in the original `flushPendingWrites()`:

```swift
if result == .cancelled, pending.isEmpty { return .success }
```

The pre-refactor `flushPendingWrites()` had no equivalent branch — a worker task that returned
`.cancelled` (e.g. because a concurrent forced `requestFlush()` cancelled it just as it finished
draining `pendingPersistence`) would previously propagate `.cancelled` all the way to
`flushPendingWrites()`'s caller even when every snapshot had actually been written to disk.

That result flows into `applicationShouldTerminate` in `Sources/Lumo/LumoApp.swift:37-46`, which
shows a "Couldn't save edits before quitting" alert on anything but `.success`. So the new branch
looks like a genuine bug fix (it avoids a false "couldn't save" alert when nothing was actually
lost), not a regression — but it is an intentional-looking behavior change that landed silently
inside a refactor whose acceptance criteria called for no behavior change, and it is not exercised
by any existing test. `testCancelledFlushIsReportedDistinctly`
(`Tests/LumoKitTests/EditPersistenceIntegrationTests.swift:202`) only covers cancelling the calling
`Task` itself (`Task.isCancelled` true), not the case where the *worker* task returns `.cancelled`
while `pending` is already empty.

## Acceptance criteria

- [ ] Confirm with the author/PR history whether this branch was deliberate, or file it as a
      recognized fix.
- [ ] Add a regression test that drives the worker into returning `.cancelled` with `pending` empty
      (e.g. cancel a worker after its last `store.save` succeeds but before `drain` observes
      `Task.isCancelled == false`) and asserts `flush()` returns `.success`.
- [ ] No production code change expected unless the behavior turns out to be unintentional.

## Implementation notes

Non-blocking — found during LUMO-168 verification. Does not affect the LUMO-168 pass/fail
determination.

### Comment — codex @ 2026-09-04T12:52:48.589Z

Implemented and committed as 94569ae. History review confirms the cancelled+empty-pending -> success branch was introduced by the LUMO-168 refactor in 8fd2ff9; the pre-refactor AppViewModel path lacked it. It is a deliberate recognized fix for avoiding a false save-failure alert, with no production policy change. Corrected testRacedFlushReportsSuccessAfterReplacementDrainsQueue so the test-only store delay occurs after the atomic write; it now cancels/replaces the worker while save is suspended after durability, asserts both flush callers return success, pendingPersistenceCount == 0, and one durable write, and fails (cancelled vs success) when the mapping line is removed. Checks: focused regression test passed 3 consecutive runs; swift test (745 passed, 34 skipped, 0 failures); swift build -c release passed; git diff --check passed; dg validate passed with pre-existing pickup-runner model warning. scripts/check-swift-format.sh remains red only on pre-existing violations in unrelated modified files and existing lines in the persistence test/store.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T13:00:56.978Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Confirm with the author/PR history whether this branch was deliberate, or file it as a recognized fix (pass)
- [x] Add a regression test that drives the worker into returning .cancelled with pending empty and asserts flush() returns .success (pass)
- [x] No production code change expected unless the behavior turns out to be unintentional (pass)
Checks run:
- swift test --filter EditPersistenceIntegrationTests — 11 executed, 0 failures
- Mutation check: removed the `if result == .cancelled, pending.isEmpty { return .success }` line in EditPersistenceCoordinator.swift and re-ran testRacedFlushReportsSuccessAfterReplacementDrainsQueue — it failed (cancelled vs success) as expected, confirming the new test detects the regression; change reverted, tree left clean
- scripts/check-swift-format.sh — no violations in EditDocumentStore.swift, EditPersistenceCoordinator.swift, or EditPersistenceIntegrationTests.swift (remaining reported violations are pre-existing, in unrelated in-progress ImageCollection.swift)
- git status --porcelain on touched files — clean, no stray edits from review
Findings:
- None
Fixes:
- None
Verification commits:
- 94569ae
Actor: claude
Resolved model: sonnet
Pickup session: 01MTMYFCEMPKAMZUP0
Summary: Counterpoint verification passed: the cancelled+empty-pending -> success mapping in EditPersistenceCoordinator.flush() (line 132) is confirmed a deliberate fix, introduced by the LUMO-168 refactor and absent pre-refactor. Regression coverage added by widening testRacedFlushReportsSuccessAfterReplacementDrainsQueue to actually drive a worker into returning .cancelled with pending empty; mutation-tested by temporarily deleting the mapping line, which reproduces the failure this ticket describes.
