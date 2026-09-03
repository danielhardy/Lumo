---
id: LUMO-123
title: Capture hardware simultaneous batch-export + editing telemetry for LUMO-113
type: task
status: done
priority: low
agent: pi
verification_agent: claude
model: openrouter/z-ai/glm-5.3-flash
verification_model: sonnet
labels:
  - verification
  - performance
  - scheduling
created: 2026-09-02T04:15:36.899Z
updated: 2026-09-02T18:47:36.929Z
parent: LUMO-113
depends_on:
  - LUMO-113
order: zz
board: product
commits:
  - ee407fa
---

## Objective

Record the on-hardware simultaneous batch-export + editing measurement that LUMO-113's acceptance
criteria call for: editor p95 latency and worst frame gap, plus export throughput and resident
memory, while a batch export and interactive edits run at the same time.

## Context

Found during independent verification of LUMO-113 (commit `df1143b`). The scheduling/priority work
itself (bounded editor lane, support-job eviction, cancellation checks, isolated export engine) is
implemented, tested, and passing (`swift test` 594 tests / 1 known host-specific RAW failure,
`swift build -c release` clean). `docs/LUMO-113-SCHEDULING.md` explicitly documents that the
hardware capture is **not** done: "The capture is intentionally not fabricated in CI: the
repository's opt-in Metal capture procedure requires a real drawable and hardware." That capture is
one of LUMO-113's own acceptance criteria ("During simultaneous batch export and editing, record
editor p95 latency and worst frame gap as well as export throughput and memory; preserve editor
targets rather than optimizing aggregate throughput alone.") and is non-blocking for the code
change itself, but the criterion is not yet evidenced.

## Acceptance criteria

- [ ] Run the repository's opt-in Metal capture procedure on target hardware with a batch export
      running concurrently with active editing (slider drags, Info tab open, navigation).
- [ ] Record editor input-to-presentation p95 latency and worst frame gap from `LiveEditTelemetry`
      during that concurrent run, alongside export throughput and resident-memory delta.
- [ ] Record source dimensions/format, OS, commit, viewport/backing pixels, cold/warm state, and
      whether histogram/comparison/prefetch work was enabled, per `docs/LUMO-113-SCHEDULING.md`'s
      measurement-record section.
- [ ] Confirm editor targets are preserved (not just aggregate throughput) and attach the result to
      this ticket; append a short summary to `docs/LUMO-113-SCHEDULING.md`.

## Implementation notes

Low priority / non-blocking: the scheduling mechanism (isolated export `RenderEngine`, bounded
editor-lane admission, cancellation checks) is already implemented and covered by
`ImageWorkSchedulerTests`, `ExportCoordinatorTests`, and related suites. This ticket is purely the
outstanding empirical measurement, which requires real Metal hardware and cannot be fabricated in
CI. See `docs/LUMO-113-SCHEDULING.md` for the measurement-record format expected.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T18:47:36.924Z: Recorded the outstanding LUMO-113 hardware measurement: simultaneous batch export + editing on target hardware (MacBook Pro18,3 / M1 Pro / macOS 26.6 / Release / commit ee407fa, contains LUMO-113 df1143b). Added opt-in ConcurrentExportEditingBenchmark + scripts/run-lumo-123-capture.sh (xctrace) and a PreviewSurface capture-host seam for zero presentedTime hosts. Traced run (6-item ARW batch, 10 drag gestures, 10 navigation cycles, histogram enabled): editor release-to-settled p95 113.068 ms (<=200 ms target met), interactive p95 37.939 ms, 22 FPS delivered, 0 editor-lane drops, export throughput 1.683 images/s (6/6 exported, not cancelled), resident-memory delta ~122 MB. Editor targets preserved; aggregate throughput did not win over the editor. Full record: docs/LUMO-123-DSC07826-20260902-124253-summary.md; short summary appended to docs/LUMO-113-SCHEDULING.md. swift test 630/0 failures; swift build -c release clean.
