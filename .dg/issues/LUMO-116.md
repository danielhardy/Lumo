---
id: LUMO-116
title: Add benchmark suite and slow/failing-store regression tests for coalesced edit persistence
type: task
status: done
priority: medium
labels:
  - verification
  - performance
  - persistence
created: 2026-09-01T22:34:16.919Z
updated: 2026-09-01T23:34:51.929Z
parent: LUMO-110
depends_on:
  - LUMO-110
order: a0
board: product
commits:
  - 90c1b95
---

## Objective

Add benchmark suite and slow/failing-store regression tests for coalesced edit persistence

## Context

Found during counterpoint verification of LUMO-110 (commit 5a0b4b5 + a follow-up fix committed during
verification). LUMO-110's verification plan called for extending `EditDocumentStoreTests` and
`EditPersistenceIntegrationTests` with a slow/failing store, rapid cross-asset edits, long gestures,
final flush, and interrupted-write recovery, and for benchmarking 10/1,000/10,000 edited-photo
catalogs (writes, bytes, queue depth, CPU, source-switch delay, termination flush time). None of that
landed with the implementation — only a rapid-edit coalescing test was added. This is non-blocking
(the shipped behavior is correct by inspection and the full suite passes), but the acceptance
criteria around measured/benchmarked evidence and interrupted-write recovery coverage remain
unverified.

## Acceptance criteria

- [ ] `EditDocumentStoreTests`/`EditPersistenceIntegrationTests` gain a slow store (artificial delay
      hook) and a failing store, used to prove: (a) `flushPendingWrites()` genuinely waits for a save
      that is in flight when a forced flush (source switch / undo-redo / termination) restarts the
      persistence worker, and (b) a write failure keeps the dirty snapshot for retry rather than
      silently dropping it.
- [ ] A test drives a long gesture past multiple 250 ms checkpoints and asserts more than one
      intermediate write occurs (not just the final mouse-up value), per the "not indefinitely
      deferred until mouse-up" acceptance criterion.
- [ ] Benchmark 10, 1,000, and 10,000 edited-photo catalogs under sustained input and report writes,
      bytes, queue depth, CPU, source-switch delay, and termination flush time, with hardware/OS/
      commit/configuration recorded per `docs/PERFORMANCE_AUDIT_2026-09-01.md` conventions.

## Implementation notes

Adding the slow-store hook likely requires `EditDocumentStore.persist()`/`save()` to grow an
internal (non-public) artificial-delay seam, since the store is a concrete actor with no protocol
seam today — evaluate whether that's worth the surface area versus injecting delay via a wrapping
test double.

### Comment — codex @ 2026-09-01T23:31:29.855Z

Implemented and verified in commit 0342965. Added internal slow/failing EditDocumentStore seams, regression coverage for forced flush waiting, retry-preserved dirty snapshots, and 250 ms long-gesture checkpoint writes. Added opt-in 10/1,000/10,000 edited-catalog benchmark reporting writes, bytes, peak queue, CPU, source-switch delay, and termination flush time; recorded the measured baseline and environment in docs/EDIT_PERSISTENCE_BENCHMARK_2026-09-01.md. Verification: full swift test passed (574 tests, 29 expected skips), LUMO_PERSISTENCE_BENCHMARK=1 benchmark passed for all catalog sizes, swift build -c release passed, git diff --check passed, and dg validate passed with only the pre-existing pickup-runner model warning.

### Comment — claude @ 2026-09-01T23:34:48.628Z

Counterpoint verification (independent, post-human-review): PASS.

Re-ran the claimed verification steps from a clean tree at commit 0342965:
- swift build: clean.
- swift test: 574 tests, 29 expected skips, 0 failures (includes the new
  testFailingStoreCanRetryTheCompleteSnapshot, testForcedFlushWaitsForAnInFlightSlowWrite,
  testFailedPersistenceRemainsDirtyUntilAForcedRetrySucceeds, and
  testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp).
- LUMO_PERSISTENCE_BENCHMARK=1 swift test --filter EditPersistenceBenchmarkTests: passed;
  reproduced writes/bytes and timings consistent with docs/EDIT_PERSISTENCE_BENCHMARK_2026-09-01.md
  (10/1,000/10,000 catalogs; e.g. 10,000-record case ~3.3s CPU, ~14MB write, matching the recorded baseline).
- swift build -c release: clean.
- git diff --check and dg validate: clean (only the pre-existing pickup-runner model warning).

All three acceptance criteria are met: slow-store forced-flush wait, failing-store dirty-snapshot
retry, multi-checkpoint long-gesture writes, and the recorded 10/1,000/10,000 benchmark with
hardware/OS/commit/configuration.

Maintainability finding (fixed inline, localized, no behavior change): EditDocumentStore.swift
added `saveConcurrency`/`peakSaveConcurrency` counters that were write-only — never read by any
test or the benchmark, which measures queue depth via AppViewModel.peakPendingPersistenceCount
instead. Removed the dead fields and their bookkeeping in persist() (commit 90c1b95). Full
574-test suite re-verified green after the removal.

No blockers found. No child tickets needed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T23:34:51.927Z: Independent counterpoint verification passed: rebuilt, reran full 574-test suite and the opt-in 10/1,000/10,000 persistence benchmark, verified release build/git diff/dg validate. Removed dead write-only save-concurrency counters from EditDocumentStore.swift (commit 90c1b95) as a localized cleanup; re-verified green after.
