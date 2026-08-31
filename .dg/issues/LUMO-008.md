---
id: LUMO-008
title: Persist per-photo edit records with atomic recovery
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:19.524Z
updated: 2026-08-31T13:05:08.595Z
depends_on:
  - LUMO-007
  - LUMO-061
estimate: 5
order: zv
board: product
---

## Objective

Implement the simplest local edit store that safely survives relaunch without modifying source files.

## Context

Part of **Epic 1 — Durable per-photo edit domain**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Choose and document an internal JSON or lightweight database representation based on measured complexity.
- Key records by stable source identity and retain bookmark/relink information.
- Write atomically and preserve last-known-good data on corruption or interruption.
- Load asynchronously away from the main actor.

## Acceptance criteria

- [ ] Edits survive clean quit/relaunch and folder restoration.
- [ ] RAW and standard originals are byte-for-byte untouched.
- [ ] Missing, malformed, and partially written records fail safely with actionable status.
- [ ] Writes are atomic and migrations are testable.

## Verification

- Add persistence round-trip, corrupt-record, missing-source, and migration tests.
- Assert persistence I/O is not main-actor bound.

## Out of scope

- Cloud sync.
- A Lightroom-scale catalog.

### Comment — codex @ 2026-08-31T03:37:54.326Z

Implemented and verified in commits 129834a, 7fc4d59, 5929c23, 1da9e19, and b6c4114. Added actor-isolated EditDocumentStore with a versioned JSON envelope, canonical source paths, security-scoped bookmark relinking, atomic primary writes, last-known-good .bak recovery, safe corruption/newer-schema handling, and legacy migration. Wired AppViewModel per-photo sessions to asynchronous disk load/save with ordered snapshots and actionable recovery status; originals remain untouched. Added round-trip, relaunch, missing-source, corruption/partial-record, recovery, relink, migration, atomic-backup, newer-schema, and off-main-actor tests. Verification: swift test passed (325 tests, 20 expected skips); swift build passed; swift build -c release passed; dg validate passed with pre-existing warnings only.

### Comment — claude @ 2026-08-31T03:40:45.616Z

## Verification report (independent counterpoint pass)

**Checks run:** `swift build` (debug) — clean. `swift test` — 325 tests, 20 expected skips, 0 failures. Reviewed EditDocumentStore.swift, PhotoAssetID.swift, EditDocument.swift, AppViewModel.swift wiring, ExportCoordinator.swift, and the new test files (EditDocumentStoreTests, EditDocumentTests, EditPersistenceIntegrationTests, PhotoEditSessionTests).

**Confirmed working:** atomic primary write + `.bak` last-known-good recovery, corrupt/malformed/missing-source handling, legacy bare-map and versionless-envelope migration, newer-schema rejection without overwrite, security-scoped-bookmark relink-and-rekey, actor-isolated I/O (asserted off-main-actor by test), originals untouched (round-trip test asserts source bytes unchanged).

**Blocker found — LUMO-061 (urgent, now a dependency of this issue):** `AppViewModel.saveActiveDocument()` queues each edit's disk write on an unstructured `Task` and returns immediately; `AppDelegate` never overrides `applicationShouldTerminate(_:)` to defer termination until that queue drains. An edit made immediately before Cmd+Q can be lost, because the process can exit before the in-flight `EditDocumentStore.save` completes. This directly contradicts the "Edits survive clean quit/relaunch" acceptance criterion. The existing relaunch test doesn't catch it because it explicitly waits for `store.status == .ready` before "relaunching," sidestepping the exact race a real quit would hit. Filed as LUMO-061 with a proposed fix (flush hook + `.terminateLater`/`NSApp.reply` in AppDelegate) and a test that doesn't rely on the store already being ready.

**Non-blocking, filed as backlog LUMO-062:** `EditDocumentStore.load(for:)`'s relink path can silently discard a prior actionable status (e.g. `.recoveredFromBackup`) in favor of, or in favor over, `.relinked` depending on which happened — narrow edge case, no data loss, only a suppressed status message.

**Fixed in this pass (verification commit 06652fb):** removed a stale/duplicate doc comment in `ExportCoordinator.performBatchExport` left over from this change (the old "per-image documents arrive in Step 11" text wasn't replaced, just appended to).

**Disposition:** moving back to `review` pending LUMO-061. Lease cleared.

### Comment — claude @ 2026-08-31T13:05:05.275Z

## Verification report (independent counterpoint pass, re-verification after LUMO-061/LUMO-062)

**Context:** this issue was previously moved back to `review` after finding an urgent blocker (LUMO-061: no termination flush, risking a lost last-second edit) plus a non-blocking issue (LUMO-062: relink status masking). Both are now `done`, and this issue is back in `verification`.

**Branch note:** LUMO-061 and LUMO-062 were implemented and verified on sibling branches (`agent/lumo-061`, `agent/lumo-062`) that rebased LUMO-008's original commits onto new hashes — this worktree's branch (`agent/lumo-008`, HEAD `06652fb`) never received those fixes. Confirmed the pre-fix trees were byte-identical (`git diff 129834a af5363e` empty) before cherry-picking the three fix commits onto this branch: `b5b8176` (flush before termination, from `agent/lumo-061`), `db0e3f8` and `2fb3757` (relink status combining + dedupe, from `agent/lumo-062`). `git diff HEAD agent/lumo-062` is now empty — this branch and the latest fixed state are content-identical.

**Checks run:** `swift build` — clean. `swift test` — 327 tests, 20 expected skips, 0 failures. `swift build -c release` — clean. `dg validate` — OK, only pre-existing unrelated warnings. `git status --porcelain` — clean (aside from the pre-existing untracked `.dg`).

**Re-reviewed:**
- `AppDelegate.applicationShouldTerminate(_:)` (Sources/Lumo/LumoApp.swift) returns `.terminateLater`, awaits `AppViewModel.flushPendingWrites()`, then replies; `terminationFlushInProgress` guards a double AppKit call. `flushPendingWrites()` loops re-reading `persistenceTask` after each await, so a write queued while suspended is still caught.
- `testTerminationStyleFlushPersistsAnImmediateEdit` exercises the real race (edit + immediate flush, no `waitUntilStoreReady`) and round-trips through a second `AppViewModel` instance.
- `EditDocumentStore.Status.combining` now chronologically merges actionable statuses instead of one silently overwriting the other, with `Equatable`-based dedup so a second unrelated relink doesn't repeat an earlier message. `testBackupRecoveryAndRelinkReportBothActionableEvents` and `testSecondRelinkOnTheSameStoreDoesNotDuplicateTheMessage` both pass and assert the right thing.

**Disposition:** no blockers, no further fixes needed. All four acceptance criteria hold with LUMO-061 and LUMO-062 folded in. Moving to `done`.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
