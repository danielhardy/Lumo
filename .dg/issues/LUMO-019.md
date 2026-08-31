---
id: LUMO-019
title: Build progressive cancellable folder ingestion and metadata loading
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:library
  - phase:3
created: 2026-08-30T18:30:23.370Z
updated: 2026-08-31T15:21:33.971Z
depends_on:
  - LUMO-018
estimate: 5
order: a0
board: product
branch: agent/lumo-019
commits:
  - f135ef0
---

## Objective

Publish useful assets incrementally while folder scanning and metadata extraction stay off the main actor.

## Context

Part of **Epic 3 — Folder library and rapid culling**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Scan supported formats recursively with deterministic ordering.
- Publish batches rather than waiting for the entire traversal.
- Separate cheap discovery from deferred dimensions/capture/camera metadata.
- Cancel cleanly on folder switch or rescan.

## Acceptance criteria

- [ ] Visible library content begins appearing before a large scan completes.
- [ ] Folder switching cannot mix results from two scans.
- [ ] Metadata parsing never blocks the main actor.
- [ ] Unsupported, unreadable, and disappearing files are skipped/reported without aborting the scan.

## Verification

- Add incremental delivery, cancellation, ordering, and failure-isolation tests.

## Out of scope

- Filesystem watcher synchronization unless needed for MVP refresh.

### Comment — codex @ 2026-08-31T14:58:24.088Z

Implemented and committed as f135ef0. Folder discovery now publishes incremental batches with deterministic accumulated ordering and generation-token cancellation; deferred ImageIO metadata is cancellable/off-main-actor and stale photo metadata is suppressed; unreadable/disappearing files are reported and isolated; scan progress/warnings are visible in the source browser. Added regression tests for incremental delivery, folder-switch isolation, metadata loading, ordering, and failure isolation. Verification: swift test passed (336 tests, 20 expected skips), focused LibraryScanTests passed (17), swift build -c release passed, git diff --check passed, dg validate passed with only pre-existing warnings.

### Comment — claude @ 2026-08-31T15:21:31.686Z

## Independent verification (counterpoint agent)

Reviewed the full diff in f135ef0 against the acceptance criteria and re-ran all declared checks independently (not just re-trusting the prior report).

**Checks run:**
- `swift build` — clean.
- `swift test` — 336 tests, 0 failures, 20 expected skips (full suite, not just the focused file).
- `swift test --filter LibraryScanTests` — 17/17 passed, including the 4 new regression tests for incremental delivery, folder-switch isolation, deferred metadata, and unreadable-file isolation.
- `swift build -c release` — clean.
- `git diff --check f135ef0~1 f135ef0` — clean.
- `dg validate` — OK, only pre-existing warnings (unrelated model name, LUMO-017 context completeness).
- Manual read of `ImageCollection.swift`, `ImageMetadata.swift`, `AppViewModel.swift`, `SourceBrowserView.swift` diffs; grepped for Swift 6 escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`) — none introduced, consistent with the project's zero-opt-out concurrency rule.

**Design points verified as correct, not just passing:**
- `scanGeneration` is checked both in the discovery consumer loop and in `applyMetadata`, so a folder switch mid-scan cannot let a stale batch or a stale metadata read mutate `items` — matches "folder switching cannot mix results from two scans."
- `thumbnailGeneration` increment was correctly moved out of `enqueueThumbnails()` (called once per batch) and into `cancelThumbnailWork()` (called once per scan/clear); leaving it in the old per-call location would have invalidated in-flight thumbnail jobs on every batch.
- Metadata reads run in a `Task.detached` consumer over an `AsyncStream`, hopping to `MainActor.run` only to apply results — matches "metadata parsing never blocks the main actor."
- Unreadable/disappearing files produce a `.failure` outcome that both records a `ScanWarning` and removes the item (plus its queued thumbnail job) from `items`, without aborting the rest of the scan.
- `AsyncStream` cancellation propagation (task cancel → `onTermination` → detached producer `Task.isCancelled` check) is the standard library's documented cancellation-aware behavior, so the "cancel cleanly" criterion holds even though it isn't instantaneous mid-file.

**Non-blocking observations (not filed as child tickets — cosmetic/edge-case, well within existing patterns):**
- `scanWarnings` grows unboundedly for pathological folders with very many bad files; only the last is ever shown in `SourceBrowserView`. Low impact given typical folder sizes.
- The per-batch `self.items.contains(where: { $0.id == item.id })` dedup check is O(n) per item (O(n²) over a full scan); acceptable at the UUID-compare cost and scan sizes involved here, but worth a `Set` if folder sizes grow substantially in a future change.

No blockers found. Verification passes.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T15:21:33.969Z: Independent verification passed: full swift test suite (336/0 failures), release build, git diff --check, and dg validate all clean; diff reviewed against acceptance criteria with no blockers.
