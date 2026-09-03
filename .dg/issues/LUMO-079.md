---
id: LUMO-079
title: LiveEdit telemetry measures drawable submission, not true presentation time
type: task
status: done
priority: low
labels:
  - verification
created: 2026-09-01T02:27:20.117Z
updated: 2026-09-01T05:32:04.579Z
depends_on:
  - LUMO-068
order: a0
board: product
commits:
  - 9421b67
---

## Objective

LiveEdit telemetry measures drawable submission, not true presentation time

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-01T05:28:14.248Z

Implemented in commit 9421b67. LiveEdit telemetry now uses the monotonic Core Animation host-time clock, records GPU completion from MTLCommandBuffer.gpuEndTime, and records drawablePresentation only from MTLDrawable.addPresentedHandler using drawable.presentedTime. Submitted/in-flight revisions remain correlated across overlapping frames; skipped drawables are excluded. Added regression coverage proving GPU completion alone is not presentation. Verification: swift test (463 passed, 25 expected skips), swift build -c release, git diff --check, and dg validate passed; validate reports only the pre-existing runner-model warning.

### Comment — claude @ 2026-09-01T05:31:58.022Z

## Independent counterpoint verification — PASS

Reviewed commit 9421b67 (LiveEditTelemetry + PreviewCoordinator + PreviewSurface + regression test).

Checks run:
- `swift build`: clean.
- `swift test`: 463 passed, 25 expected skips, 0 failures — matches the claimed run.
- `swift build -c release`: clean.
- `git diff --check 9421b67^ 9421b67`: clean (no whitespace errors).
- `dg validate`: OK, only the pre-existing `agents.pickup.runner` model warning.

Code review findings:
- All timestamps (input, renderStart/End, gpuCompletion, drawablePresentation) now consistently
  use `LiveEditTelemetryClock.now` (CACurrentMediaTime host-time clock), matching the clock domain
  of `MTLCommandBuffer.gpuEndTime` and `MTLDrawable.presentedTime`. No stray
  `Date.timeIntervalSinceReferenceDate` usages remain in the touched files — this was the actual
  defect the ticket describes, and it's fixed.
- Traced `PreviewSurface`'s revision bookkeeping (`pendingGPURevision`, `telemetryByRevision`,
  `submittedTelemetryRevisions`) across interleaved present()/submit/gpuCompletion/presented
  callback orderings, including: rapid re-present before a draw, a submitted-but-not-yet-completed
  revision surviving a newer present(), skipped-drawable handling (presentedTime == 0 drops the
  sample instead of recording a false presentation), and `clear()` invalidating in-flight state on
  source switch. No correctness issue found; behavior matches the "skipped drawables excluded"
  claim and is covered by the new `testLiveEditReportDoesNotTreatGPUCompletionAsPresentation` test.
- Checked handler registration order against the Metal SDK headers
  (`MTLDrawable.h`/`MTLCommandBuffer.h`): both `addCompletedHandler` and `addPresentedHandler` are
  registered before `commandBuffer.commit()`, which is the documented constraint — no ordering bug.
- Swift 6 concurrency: completion/presented handler closures run off-main-actor and correctly hop
  back via `Task { @MainActor in ... }` with `[weak surface]` captures; no data races, no opt-outs
  introduced.

No blockers, no follow-up child tickets needed — this is a clean, well-scoped fix with adequate
regression coverage.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T05:32:04.578Z: Independent counterpoint verification passed: build/tests/release build/diff-check/dg validate all match claims; reviewed clock-domain consistency and PreviewSurface revision bookkeeping, no defects found.
