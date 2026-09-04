---
id: LUMO-165
title: "Audit: complete Look preview jobs on cancellation and eviction"
type: bug
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - bug
  - performance
  - look
  - audit
created: 2026-09-03T23:28:46.385Z
updated: 2026-09-03T23:28:46.385Z
order: zzzh
board: product
---

## Objective

Ensure every admitted Look-preview job reaches a terminal result when cancelled, evicted, or dropped.

## Context

`LookPreviewCoordinator` bridges scheduler work with `withCheckedContinuation`, but `ImageWorkScheduler` can remove queued jobs during cancellation or priority eviction without invoking the operation or notifying its waiter. That can leave `inFlight` entries and callers suspended indefinitely, producing stuck or permanently blank Look thumbnails.

## Acceptance criteria

- [ ] Cancellation, queue eviction, rejection, and successful execution all complete the preview request exactly once.
- [ ] `inFlight` entries are removed on every terminal path, including task cancellation and render failure.
- [ ] Scheduler APIs expose an explicit terminal outcome rather than silently deleting admitted jobs.
- [ ] Regression tests cover queue-full eviction, `cancelAll`, individual cancellation, and a subsequent retry for the same Look.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
