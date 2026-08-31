---
id: LUMO-015
title: Schedule visible, adjacent, grid, and background image work by priority
type: task
status: done
priority: high
labels:
  - mvp
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:22.050Z
updated: 2026-08-31T14:01:55.229Z
depends_on:
  - LUMO-013
  - LUMO-014
estimate: 5
order: a0
board: product
commits:
  - d3b441b
---

## Objective

Ensure thumbnail and precache work yields to active editing and photo navigation.

## Context

Part of **Epic 2 — Render orchestration, caching, and observability**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define priorities for active editor, adjacent filmstrip, visible grid, and background work.
- Apply backpressure to folder-scale thumbnail generation.
- Cancel work that scrolls out of relevance where safe.
- Avoid serializing all thumbnails behind the render actor's GPU-critical path.

## Acceptance criteria

- [ ] Active editor work starts ahead of queued background thumbnails.
- [ ] Thumbnail production has a bounded concurrency limit.
- [ ] Fast scrolling/navigation does not leave an unbounded obsolete queue.
- [ ] Adjacent-photo preparation improves perceived switching without starving the current photo.

## Verification

- Add scheduler ordering, cancellation, and bounded-queue tests.

## Out of scope

- Distributed rendering.
- Speculative work without a measurable consumer.

### Comment — codex @ 2026-08-31T13:59:18.664Z

Implemented in cfda50b: added the shared ImageWorkScheduler with active-editor priority, four-worker bounded thumbnail concurrency, a capped priority-aware queue, cancellation/reprioritization around adjacent photos, and replenishment for large folders. Routed previews and both file/data thumbnail paths through it. Added deterministic ordering, cancellation, and bounded-queue tests. Verification: swift test (311 passed, 20 skipped), swift build -c release, git diff --check, and dg validate (only pre-existing warnings).

### Comment — claude @ 2026-08-31T14:01:52.768Z

Independent verification (counterpoint pass), agent=claude.

Reviewed ImageWorkScheduler.swift, ImageCollection.swift, and AppViewModel.swift's routing of preview/baseline renders through the new editor lane, plus ImageWorkSchedulerTests.swift.

Findings:
- Correctness: admitThumbnail() silently dropped a thumbnail job (without running it and without incrementing droppedThumbnailCount) whenever maxQueuedThumbnails == 0, even when running capacity existed — `pending.max(by:)` returns nil on the empty pending list and the old guard returned before ever inserting into `queued`. Not reachable via any current caller (both ImageCollection and AppViewModel use `.default`, maxQueuedThumbnails: 24), but latent and worth closing since Configuration is a public-ish knob. Fixed in d3b441b: only attempt eviction when there is something to evict; otherwise the job is queued directly for immediate pump(). Added `testThumbnailRunsImmediatelyWhenTheQueueIsDisabled` (fails pre-fix, passes post-fix).
- Confirmed the editor lane's `!running.values.contains(where: { $0.lane == .editor })` rule serializes `editor:preview` and `editor:baseline` jobs that previously ran as two independent unstructured Tasks. Not a regression: RenderEngine already serializes GPU work through its own actor, so wall-clock behavior is unchanged; this just makes the serialization explicit at the scheduler layer too.
- No other correctness, security, or concurrency issues found. Swift 6 strict concurrency holds (JobID/Priority/Lane/Configuration all Sendable, Operation is `@MainActor @Sendable`, no opt-outs introduced).

Verification run (post-fix):
- `swift build`: clean.
- `swift test`: 312 passed, 20 skipped, 0 failures (up from 311 — added regression test).
- `swift build -c release`: clean.
- `git diff --check`: clean.
- `dg validate`: OK (only pre-existing warnings: agents.pickup.runner model name, LUMO-011 context completeness).

Verification commit: d3b441b "Fix silent job loss when the thumbnail queue is disabled".

Acceptance criteria re-checked against ImageWorkSchedulerTests.swift and AppViewModel/ImageCollection routing: active-editor priority ✓, bounded thumbnail concurrency ✓, bounded queue with eviction of lowest-priority work ✓, adjacent-photo reprioritization/cancellation on navigation ✓ (ImageCollection.reprioritizeThumbnails).

Verdict: PASS. Moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T14:01:55.227Z: Independent verification passed; fixed a latent silent-drop bug in admitThumbnail() when maxQueuedThumbnails==0.
