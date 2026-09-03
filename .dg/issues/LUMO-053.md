---
id: LUMO-053
title: Add batch progress, cancellation, collision handling, and failure isolation
type: task
status: done
priority: high
labels:
  - mvp
  - epic:export
  - phase:9
created: 2026-08-30T18:30:35.423Z
updated: 2026-09-02T17:12:52.287Z
depends_on:
  - LUMO-052
  - LUMO-015
estimate: 5
order: a0
board: product
commits:
  - 749082a
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 749082a
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-02T17:12:52.286Z
  session: 01MTKCOBJ9GP13Q4MP
---

## Objective

Make long selected exports controllable and trustworthy without aborting the whole run for one bad file.

## Context

Part of **Epic 9 — Reliable full-resolution export**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Report completed/total/current item and final success/failure/cancel summary.
- Cancel between expensive stages and clean incomplete outputs safely.
- Use deterministic collision-resistant naming.
- Bound concurrent full-resolution work to protect memory.

## Acceptance criteria

- [ ] Cancel stops new work and leaves completed valid files intact.
- [ ] One failed source is reported and remaining files continue.
- [ ] No two selected assets overwrite one another.
- [ ] Memory does not scale linearly with batch length.

## Verification

- Add failure, cancellation, collision, partial-output, and bounded-concurrency tests.

## Out of scope

- Background exports after app quit.

### Comment — codex @ 2026-09-02T17:08:22.037Z

Implemented cancellable, failure-isolated batch export. Added completed/total/current-item progress, explicit cancellation outcomes, atomic temporary-file commits with cleanup, deterministic reserved collision-safe names, serial full-resolution work bounded to one active render, and status-bar Cancel/progress UI. Added regressions for failure continuation/reporting, cancellation with completed-file preservation and partial cleanup, collision handling, progress/current item, cancellation summary, and concurrency bound. Verification: swift test (626 passed, 13 expected skips), swift build -c release, git diff --check, and dg validate passed; validate retains only pre-existing pickup-model and LUMO-050 context warnings.

### Comment — claude @ 2026-09-02T17:12:48.282Z

## Counterpoint verification report (independent review)

**Verdict: PASS — no blockers.**

Reviewed commit 749082a against the objective and acceptance criteria, focused on `ExportCoordinator.performBatchExport`/`cancelBatchExport` and the new `ExportCoordinatorTests`/`FakeRenderEngine` coverage.

**Correctness**

- Cancel: `cancelBatchExport()` sets a `batchCancellationRequested` flag and cancels `batchTask`; the loop checks both before starting a new item and again after every await inside an item (post-resolve, pre-render, post-render, post-write), so a cancel during the current item's encode still lets that encode finish but discards the result rather than committing it. Traced `testBatchExportCanBeCancelledBetweenItemsAndKeepsCompletedFiles`: first item's file survives, second item's encode is allowed to complete but its write is skipped, third item never starts — matches "cancel leaves completed valid files intact."
- Partial-output safety: `Self.write` writes to a hidden `.<name>.<uuid>.partial` temp file, then `FileManager.moveItem` (which does not replace an existing destination) commits it; a `defer` removes the temp file whenever `committed` is never set, covering both cancellation and write-failure exits. No partial or `.partial` file is left behind (asserted in the cancellation test).
- Failure isolation: a per-item catch (distinct from the `CancellationError` catch) counts the failure, reports it via `onStatus`, and continues the loop — verified with a genuinely undecodable source sandwiched between two good ones.
- Collision handling: `uniqueExportURL` (disk-existence check) is combined with an in-batch `reservedPaths` set keyed on the standardized path, reserved before each render starts. This covers both pre-existing files on disk and same-named items within one batch (e.g. two `DSC001.jpg` from different source subfolders), and reservation happens even for items that later fail, so numbering stays deterministic regardless of success/failure order.
- Bounded work: the batch loop is fully serial (`await` per item, no concurrent task spawning), so only one full-resolution raster/encoded `Data` is ever alive; `FakeRenderEngine.maxConcurrentEncodes` observably pins at 1. `reservedPaths` is the only structure that grows with batch length, and it holds strings, not image data, so memory does not scale with resolution × count.
- Swift 6 mode: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` introduced; `BatchItem`/`SourceAccess` are `Sendable` value types, and the mutable `batchCancellationRequested`/`batchTask` stay `@MainActor`-isolated on `ExportCoordinator`.

**Findings:** none rising to a backlog ticket. (Minor, non-actionable observation: `reservedPaths` compares paths case-sensitively while APFS is case-insensitive by default, so two items differing only by case could spuriously report a failure instead of colliding silently — strictly safer than an overwrite, and not a violation of any acceptance criterion, so not filed.)

**Checks run (this session)**

- `swift test` — 626 executed, 13 expected skips, 0 failures (includes all 17 `ExportCoordinatorTests`, cancellation/collision/failure/progress/bounded-concurrency cases individually re-run and passing).
- `swift build -c release` — clean.
- `git diff --check` — clean.
- `dg validate` — OK (pre-existing pickup-model and LUMO-050 context warnings only).

No verification commits to product code; issue bookkeeping only.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T17:12:52.287Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- 749082a
Actor: claude
Resolved model: sonnet
Pickup session: 01MTKCOBJ9GP13Q4MP
Summary: Counterpoint verification passed: independent review of 749082a found no blockers; all acceptance criteria hold (cancel preserves completed files, partial outputs cleaned up, per-item failure isolation, deterministic collision-safe naming, serial/bounded full-resolution work). Checks: swift test (626 cases, 13 expected skips, 0 failures), swift build -c release, git diff --check, dg validate OK.
