# LUMO-113 render scheduling

The main-actor `ImageWorkScheduler` is the admission point for work that competes for the display
renderer. Its editor lane is serialized because `RenderEngine` owns mutable Core Image/RAW state.
Visible interactive and settled preview requests use `activeEditor` priority; comparison and
histogram work use lower priorities, and adjacent prefetch uses the lowest render priority. The
editor backlog is capped at four jobs. A newly admitted visible request drops queued support jobs,
which are safe to recreate after the visible frame is confirmed.

Cancellation is checked by the scheduler before invoking an operation and by renderer-facing
operations before expensive work and at safe stage boundaries. Core Image calls that have already
entered a non-preemptible operation may finish, but source/revision checks prevent publication and
the scheduler does not admit a replacement support queue behind obsolete work.

Histogram and comparison work is tied to the display lifecycle. `PreviewSurface` confirms a managed
frame from the drawable-presented callback; only then does `AppViewModel` enqueue the histogram and,
when needed, the comparison baseline. Headless renderer tests use the surface's compatibility seam,
which confirms immediately because no drawable exists.

Production batch exports use a separate `RenderEngine` actor, processing context, and command queue
from the display engine. The batch loop permits one full-resolution encode at a time and does not
retain completed full-resolution results, so its intentional capacity limit is one resident full
resolution result. The display engine retains its existing bounded preview/developed-source caches;
the two engines share only the Metal device, not mutable contexts, filters, queues, or textures.

## Measurement record

The code records editor input-to-presentation telemetry, p95 latency, and worst frame gap through
`LiveEditTelemetry`. A simultaneous batch-export capture must be run on the target Mac in Release
configuration and must record those values alongside export throughput and resident-memory delta.
The capture is intentionally not fabricated in CI: the repository's opt-in Metal capture procedure
requires a real drawable and hardware. Record source dimensions/format, OS, commit, viewport/backing
pixels, cold/warm state, and whether histogram/comparison/prefetch work was enabled with the result.

## Hardware capture (LUMO-123)

The outstanding simultaneous batch-export + editing capture was taken on the target Mac (MacBook
Pro18,3, M1 Pro, macOS 26.6, Release, commit `0cc8df8`, which contains LUMO-113 `df1143b`):
`ConcurrentExportEditingBenchmark` drives the shipping export/editor/scheduler stack with real
drawables. With a 6-item ARW batch export running concurrently with slider drags, navigation, and
Info-tab histogram work: editor release-to-settled p95 `113.068 ms` (≤ 200 ms — met), interactive
p95 `37.939 ms`, editor delivered 22 FPS with zero scheduler editor-job drops, export throughput
`1.683` images/s, resident-memory delta ~122 MB. Editor targets are preserved; aggregate throughput
did not win over the editor. Full record:
[LUMO-123 capture summary](LUMO-123-DSC07826-20260902-124253-summary.md).
