---
id: LUMO-061
title: Flush pending edit-store writes before app termination
type: task
status: done
priority: urgent
labels:
  - verification
  - mvp
created: 2026-08-31T03:40:02.999Z
updated: 2026-08-31T04:05:47.407Z
order: zq
board: product
---

## Objective

Guarantee that the last edit made before a clean app quit is actually written to disk, closing the gap between LUMO-008's async persistence design and its own acceptance criterion "Edits survive clean quit/relaunch."

## Context

Found during LUMO-008 verification. `AppViewModel.saveActiveDocument()` (Sources/LumoKit/ViewModels/AppViewModel.swift:910-940) queues each edit snapshot onto an unstructured `persistenceTask` chain and returns immediately — the actual `EditDocumentStore.save` await happens off the caller's stack. `AppDelegate` (Sources/Lumo/LumoApp.swift:14-23) implements `applicationShouldTerminateAfterLastWindowClosed` but not `applicationShouldTerminate(_:)`, so nothing defers process exit until that queued write lands. Swift Concurrency tasks are abandoned when the process exits — there is no `flush()`/`waitForPendingWrites()` API on `AppViewModel` or `EditDocumentStore`, and grep confirms no caller awaits `persistenceTask` anywhere.

Concretely: a user drags a slider, then immediately presses Cmd+Q. `saveActiveDocument()` fires the write task and returns; SwiftUI/AppKit's default termination path does not wait for it; the process can exit before the task's `await store.save(...)` completes, silently dropping that last edit. The existing relaunch test (`EditPersistenceIntegrationTests.testEditedPhotoSurvivesAViewModelRelaunch`) does not catch this because it explicitly waits for `store.status == .ready` before "relaunching," which sidesteps exactly the race a real quit would hit.

## Scope

- Add a way to wait for all queued/in-flight `EditDocumentStore` writes to finish (e.g. expose the pending task chain, or an explicit `flush()` on `AppViewModel`/`EditDocumentStore`).
- Override `applicationShouldTerminate(_:)` in `AppDelegate` to return `.terminateLater`, await the flush, then call `NSApp.reply(toApplicationShouldTerminate:)`.
- Add a regression test that simulates an edit immediately followed by a termination-style flush call (without the artificial `waitUntilStoreReady` used today) and asserts the edit is on disk afterward.

## Acceptance criteria

- [ ] An edit made immediately before quit is guaranteed to be persisted before the process exits.
- [ ] A test exercises this without relying on the store already being `.ready`.
- [ ] No change to on-disk schema or existing store API contracts.

## Out of scope

- Crash recovery for a force-quit or kill -9 (only the clean-quit path is in scope, matching LUMO-008's own acceptance criterion).


### Comment — codex @ 2026-08-31T04:04:23.302Z

Implemented clean-quit edit persistence flush in 3cbf2a8. AppViewModel now exposes flushPendingWrites() that drains the ordered persistence chain, including writes queued while suspended. AppDelegate owns the shared view model, defers termination with .terminateLater, flushes, then replies to NSApp. Added a regression relaunch test that edits and immediately flushes without waiting for store readiness. Verification: swift test passed (325 tests, 20 skipped, 0 failures); swift build -c release passed; dg validate passed; git diff --check passed.


### Comment — claude @ 2026-08-31T04:05:45.677Z

## Independent verification — PASS

Reviewed commit 3cbf2a8 (Flush edit persistence before app termination) as an independent counterpoint review after human review.

**Correctness**
- `AppViewModel.flushPendingWrites()` loops on `persistenceTask`, re-reading it after each `await`. Since `AppViewModel` is `@MainActor` and `saveActiveDocument()` chains each new write onto `previous` before publishing itself as `persistenceTask`, a write queued while `flushPendingWrites()` is suspended is picked up by the next loop iteration — no last-edit race.
- `EditDocumentStore` is itself an `actor`, so its `save` calls serialize independently of the chain; the chain exists to keep `AppViewModel`'s status/generation bookkeeping ordered, not to serialize disk I/O by itself.
- `AppDelegate.applicationShouldTerminate(_:)` returns `.terminateLater`, awaits the flush inside a `@MainActor` `Task`, then replies via `sender.reply(toApplicationShouldTerminate:)`. The `terminationFlushInProgress` guard prevents a second AppKit-triggered call from racing the reply.
- `ContentView` now takes an injected `AppViewModel` (`@ObservedObject`) so `AppDelegate` and the SwiftUI scene share one instance — required for the flush to see the same `persistenceTask` the UI queued.

**Test coverage**
- `testTerminationStyleFlushPersistsAnImmediateEdit` replaces the old test that relied on `store.status == .ready`. It now edits and calls `flushPendingWrites()` immediately, then relaunches a second `AppViewModel` against the same store file and asserts the edit round-trips — this is the actual race described in the issue, not sidestepped.

**Scope / API contract**
- No on-disk schema change. `flushPendingWrites()` and the new `AppViewModel()`/`ContentView(viewModel:)` initializers are additive; no existing store API changed.
- No `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` introduced — Swift 6 strict concurrency stays at zero escape hatches.

**Checks run**
- `swift build` — clean
- `swift build -c release` — clean
- `swift test` — 325 tests, 20 skipped, 0 failures
- `dg validate` — OK (only pre-existing unrelated warnings)
- `git status --porcelain` — clean tree (aside from the pre-existing `.dg` symlink)

No blockers. No localized fixes needed — moving to done.
