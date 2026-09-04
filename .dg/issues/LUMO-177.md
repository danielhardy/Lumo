---
id: LUMO-177
title: Regression test for LUMO-175 raced flush does not exercise the fix
type: task
status: done
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-04T11:39:19.207Z
updated: 2026-09-04T14:28:15.560Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: testRacedFlushReportsSuccessAfterReplacementDrainsQueue exercises the LUMO-175 fix (fails when EditPersistenceCoordinator.flush()'s cancelled/empty special-case is removed).
      result: pass
      notes: "Reproduced the original finding's experiment: temporarily deleted `if result == .cancelled, pending.isEmpty { return .success }` from EditPersistenceCoordinator.flush() and reran the targeted test. It now fails with `XCTAssertEqual failed: (\"cancelled\") is not equal to (\"success\")` at EditPersistenceIntegrationTests.swift:267, confirming the test genuinely exercises the fix. Restored the coordinator; git diff clean. Root cause fix (commit 0109309) moved EditDocumentStore's artificial write delay from a blocking Thread.sleep inside persist() to a non-blocking Task.sleep (wrapped in Task.detached) inside save(), and added a writeStartSignal AsyncStream so the test synchronizes on an actual durable-write event instead of polling an actor-isolated counter that was unreachable while the actor was blocked."
    - criterion: The save() signature change (throws -> async throws) and the new writeStartSignal parameter do not break other callers or change production behavior.
      result: pass
      notes: The only production caller, EditPersistenceCoordinator.drain() (line 88), already calls `try await store.save(...)`. All existing test call sites (EditDocumentStoreTests, ExportCoordinatorTests, ComparisonModeTests, EditPersistenceIntegrationTests) already use `try await`. writeStartSignal defaults to nil and artificialWriteDelay defaults to .zero, so production stores are unaffected.
    - criterion: The Task.detached wrapper around the artificial delay is necessary, not incidental complexity.
      result: pass
      notes: "Verified experimentally by swapping in a plain `try? await Task.sleep(for: artificialWriteDelay)` (no Task.detached): testForcedFlushWaitsForAnInFlightSlowWrite then fails because the enclosing coordinator task's cancellation propagates into the structured Task.sleep and short-circuits the delay (measured elapsed ~0.2ms instead of >=250ms). Task.detached is required so the artificial delay models a disk write that, once started, completes durably regardless of the caller's cancellation. Reverted; git diff clean."
  checks_run:
    - swift build (clean)
    - swift test --filter EditPersistenceIntegrationTests (11 passed)
    - swift test --filter DevelopInspectorTests|WorkspaceNavigationTests (3 pre-existing failures, unrelated to EditDocumentStore/EditPersistenceCoordinator; stem from other uncommitted WIP already present in this shared, non-worktree-isolated checkout at session start, as previously flagged by the implementer)
    - "Manual experiment: reverted EditPersistenceCoordinator.flush()'s cancelled/empty special-case, reran testRacedFlushReportsSuccessAfterReplacementDrainsQueue (now fails as expected), restored (git diff clean)"
    - "Manual experiment: replaced Task.detached-wrapped delay with a plain Task.sleep in EditDocumentStore.save(), reran EditPersistenceIntegrationTests (testForcedFlushWaitsForAnInFlightSlowWrite now fails as expected), restored (git diff clean)"
    - git status --porcelain (clean apart from pre-existing unrelated in-progress work already present at session start)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T14:28:15.555Z
  session: 01MTN1PBYD8953784B
---

Parent: LUMO-175 (verification finding, non-blocking)

## Context

`testRacedFlushReportsSuccessAfterReplacementDrainsQueue` was added in 80e6d2d as the regression
test for LUMO-175 (a raced `flushPendingWrites()` call misreporting `.cancelled` after a
replacement worker already drained the queue). The production fix for LUMO-175 is real and
correct — `EditPersistenceCoordinator.flush()` already special-cases
`result == .cancelled, pending.isEmpty` (added incidentally by the LUMO-168 refactor, before
LUMO-175 was even filed) — but the new test does not exercise that line.

## Verified

Temporarily removed the `if result == .cancelled, pending.isEmpty { return .success }` branch
from `EditPersistenceCoordinator.flush()` (Sources/LumoKit/ViewModels/EditPersistenceCoordinator.swift)
and reran `swift test --filter testRacedFlushReportsSuccessAfterReplacementDrainsQueue`: it still
passes. Debug tracing confirmed why: `EditDocumentStore.persist()` implements
`artificialWriteDelay` with a blocking `Thread.sleep` inside the `EditDocumentStore` actor's
`persist()` method, not a suspending `Task.sleep`. That monopolizes the actor's executor for the
whole delay, so the test's synchronization point — `while await store.saveAttemptCount == 0 { ... }`
— cannot actually observe the counter until the write (and the delay) has already fully finished,
because reading an actor-isolated property requires that same executor. By the time the test's
second `flushPendingWrites()` call runs `requestFlush()`, the in-flight worker has already
completed and cleared `pending`/`task`, so nothing gets cancelled mid-write and
`result == .cancelled` is never produced. The test currently passes for a trivial reason (a single
uncontested flush), not because it reproduces the race.

## Suggested fix

Restructure the synchronization so the test can observe a write that is genuinely in flight —
e.g. have `EditDocumentStore`/the test double signal "write started" via a continuation or
`AsyncStream` from inside `persist()` before the delay (which would need `Task.sleep` or another
non-blocking delay so the actor stays reachable), rather than polling an actor-isolated counter
that is unreachable while the actor is blocked. After the fix, verify (the same way this finding
was verified) that reverting the `EditPersistenceCoordinator.flush()` special case makes the test
fail.

## Verification context

Found during LUMO-175 counterpoint verification (2026-09-04): `swift test` full suite passed
(745 tests) and `EditPersistenceIntegrationTests` passed, but experimentally reverting the
production fix line and rerunning the targeted test showed it still passes — i.e. the added
regression test provides no protection against reintroducing the LUMO-175 bug. Not a production
blocker: the fix itself is independently verified correct by reading
`EditPersistenceCoordinator.flush()`.


### Comment — codex @ 2026-09-04T14:24:30.979Z

Implemented and committed as 0109309. Reworked the artificial persistence delay to suspend asynchronously without blocking the EditDocumentStore actor, added a test-only AsyncStream durable-write signal, and synchronized testRacedFlushReportsSuccessAfterReplacementDrainsQueue on that signal before launching the replacement flush. The regression now passes with the fix and fails with cancelled vs success when the coordinator mapping is temporarily removed. Checks: focused race test passed; EditPersistenceIntegrationTests passed (11/11); swift build -c release passed; git diff --check passed; dg validate passed. Full swift test ran 752 tests with 34 expected skips, but had 6 unrelated failures in pre-existing DevelopInspectorTests and WorkspaceNavigationTests worktree changes.


### Comment — claude @ 2026-09-04T14:27:37.987Z

## Verification report — LUMO-177

**Verdict: PASS**

**What was checked**
- Reviewed commit 0109309 (EditDocumentStore.swift, EditPersistenceIntegrationTests.swift): moved the artificial write delay from a blocking `Thread.sleep` inside `persist()` to a non-blocking `Task.sleep` inside `save()`, added a `writeStartSignal: AsyncStream<Void>.Continuation?` test seam, and resynchronized `testRacedFlushReportsSuccessAfterReplacementDrainsQueue` on that signal instead of polling an actor-isolated counter.
- Independently reproduced the original finding's experiment: temporarily removed the `if result == .cancelled, pending.isEmpty { return .success }` special case from `EditPersistenceCoordinator.flush()` and reran the targeted test. **It now fails** (`"cancelled" is not equal to "success"`), confirming the regression test genuinely exercises the LUMO-175 fix, closing the gap this ticket was filed for. Reverted the experimental change; `git diff` on the coordinator is clean.
- Checked the `save()` signature change (`throws` → `async throws`): its only production caller (`EditPersistenceCoordinator.drain`) already calls it with `await`; all test call sites already use `try await`. No source break.
- Questioned whether wrapping the delay in `Task.detached` (vs. a plain `try? await Task.sleep`) is unnecessary complexity. Verified experimentally: a plain `Task.sleep` is cancellable by the enclosing (coordinator) task, and swapping it in breaks `testForcedFlushWaitsForAnInFlightSlowWrite` (measured delay drops from ≥250ms to ~0.2ms) because the forced-flush cancellation short-circuits it. `Task.detached` is required to make the delay model "the disk write already committed and can't be uncancelled" — correctly deliberate, not a defect. Reverted the experimental change; `git diff` on `EditDocumentStore.swift` is clean.
- `swift build` clean. `swift test --filter EditPersistenceIntegrationTests`: 11/11 pass, consistent with the implementer's report.
- Ran `DevelopInspectorTests`/`WorkspaceNavigationTests` (flagged by the implementer as having unrelated failures on the full suite): reproduced 3 pre-existing failures (1 in DevelopInspectorTests, 2 in WorkspaceNavigationTests/NavigationStateTests). These touch navigation/inspector selection state and security-scoped bookmark equality — unrelated files to this change (not EditDocumentStore/EditPersistenceCoordinator), and consistent with the implementer's note that they stem from other uncommitted WIP already in this shared, non-worktree-isolated checkout. Out of scope for this ticket; not caused by 0109309.

**Fixes applied:** none needed.
**Child tickets filed:** none — no broader non-blocking findings.
**Blockers:** none.

## Agent log

- 2026-09-04T14:28:15.558Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] testRacedFlushReportsSuccessAfterReplacementDrainsQueue exercises the LUMO-175 fix (fails when EditPersistenceCoordinator.flush()'s cancelled/empty special-case is removed). (pass) — Reproduced the original finding's experiment: temporarily deleted `if result == .cancelled, pending.isEmpty { return .success }` from EditPersistenceCoordinator.flush() and reran the targeted test. It now fails with `XCTAssertEqual failed: ("cancelled") is not equal to ("success")` at EditPersistenceIntegrationTests.swift:267, confirming the test genuinely exercises the fix. Restored the coordinator; git diff clean. Root cause fix (commit 0109309) moved EditDocumentStore's artificial write delay from a blocking Thread.sleep inside persist() to a non-blocking Task.sleep (wrapped in Task.detached) inside save(), and added a writeStartSignal AsyncStream so the test synchronizes on an actual durable-write event instead of polling an actor-isolated counter that was unreachable while the actor was blocked.
- [x] The save() signature change (throws -> async throws) and the new writeStartSignal parameter do not break other callers or change production behavior. (pass) — The only production caller, EditPersistenceCoordinator.drain() (line 88), already calls `try await store.save(...)`. All existing test call sites (EditDocumentStoreTests, ExportCoordinatorTests, ComparisonModeTests, EditPersistenceIntegrationTests) already use `try await`. writeStartSignal defaults to nil and artificialWriteDelay defaults to .zero, so production stores are unaffected.
- [x] The Task.detached wrapper around the artificial delay is necessary, not incidental complexity. (pass) — Verified experimentally by swapping in a plain `try? await Task.sleep(for: artificialWriteDelay)` (no Task.detached): testForcedFlushWaitsForAnInFlightSlowWrite then fails because the enclosing coordinator task's cancellation propagates into the structured Task.sleep and short-circuits the delay (measured elapsed ~0.2ms instead of >=250ms). Task.detached is required so the artificial delay models a disk write that, once started, completes durably regardless of the caller's cancellation. Reverted; git diff clean.
Checks run:
- swift build (clean)
- swift test --filter EditPersistenceIntegrationTests (11 passed)
- swift test --filter DevelopInspectorTests|WorkspaceNavigationTests (3 pre-existing failures, unrelated to EditDocumentStore/EditPersistenceCoordinator; stem from other uncommitted WIP already present in this shared, non-worktree-isolated checkout at session start, as previously flagged by the implementer)
- Manual experiment: reverted EditPersistenceCoordinator.flush()'s cancelled/empty special-case, reran testRacedFlushReportsSuccessAfterReplacementDrainsQueue (now fails as expected), restored (git diff clean)
- Manual experiment: replaced Task.detached-wrapped delay with a plain Task.sleep in EditDocumentStore.save(), reran EditPersistenceIntegrationTests (testForcedFlushWaitsForAnInFlightSlowWrite now fails as expected), restored (git diff clean)
- git status --porcelain (clean apart from pre-existing unrelated in-progress work already present at session start)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTN1PBYD8953784B
Summary: Verified: reproduced the original finding's experiment and confirmed the LUMO-177 fix (commit 0109309) genuinely closes the gap — testRacedFlushReportsSuccessAfterReplacementDrainsQueue now fails when EditPersistenceCoordinator.flush()'s cancelled/empty mapping is removed, whereas before it passed either way. Also verified the Task.detached wrapper around the artificial write delay is deliberate (not incidental complexity): swapping in a plain Task.sleep breaks testForcedFlushWaitsForAnInFlightSlowWrite because the enclosing task's cancellation would otherwise short-circuit the delay. No fixes needed; no blockers; no child tickets.
