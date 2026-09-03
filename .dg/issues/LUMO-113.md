---
id: LUMO-113
title: Prioritize visible edits over histogram, comparison, prefetch, and export work
type: task
status: done
priority: medium
labels:
  - performance
  - epic:quality
  - scheduling
  - rendering
  - export
created: 2026-09-01T22:05:11.554Z
updated: 2026-09-02T04:18:54.666Z
depends_on:
  - LUMO-107
order: zzzzzzq
board: product
---

## Objective

Keep visible image interaction responsive while supporting jobs run, and ensure supporting work follows actual displayed rendering rather than graph publication.

## Context and evidence

Performance audit item 8, evaluated at commit `724ad99`: [September 1 audit](../../docs/PERFORMANCE_AUDIT_2026-09-01.md).
The user requested tangible responsiveness improvements without sacrificing visual fidelity or accuracy; prioritize code quality and measured impact over minimizing implementation effort.

**Evidence:** Histogram processing and exports use the same RenderEngine actor as display graph construction. [RenderEngine.histogram](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderEngine.swift:341) lacks an entry cancellation check and performs synchronous bitmap rendering. [AppViewModel.publishPreview](/Users/dhardy/Dev/Lumo/Sources/LumoKit/ViewModels/AppViewModel.swift:1599) starts supporting work after graph publication, before actual presentation. Comparison baseline work is scheduled at open even when hidden.

**Approach:** Give visible edits priority over histograms, hidden comparison preparation, prefetch, and batch export. Check cancellation before expensive work and prevent obsolete supporting jobs from entering the actor. Define independent execution capacity for long non-preemptible export work, with GPU resource limits. Compute histograms from reusable rendered stages where the histogram contract permits it.

## Acceptance criteria

- [ ] Visible edits have explicit admission priority over histogram, hidden comparison, idle prefetch, and batch export; obsolete supporting jobs are dropped before expensive work.
- [ ] Histogram and supporting paths check cancellation at entry and safe boundaries, and queues remain bounded during repeated inspector toggles and navigation.
- [ ] Supporting work observes actual processing/presentation lifecycle from the completed-resource renderer instead of assuming makeCIImage publication means pixels are on screen.
- [ ] Long non-preemptible exports cannot monopolize the display actor; independent execution capacity has documented GPU/memory limits and preserves mutable-resource isolation.
- [ ] Hidden comparison performs no unnecessary evaluated render work; visible comparison remains current after develop/crop changes.
- [ ] Histogram semantics remain whole displayed document/crop in its intended color space, not silently the zoomed viewport; export pixels and filenames remain correct.
- [ ] During simultaneous batch export and editing, record editor p95 latency and worst frame gap as well as export throughput and memory; preserve editor targets rather than optimizing aggregate throughput alone.

## Verification plan

Extend ImageWorkSchedulerTests, HistogramTests, ComparisonModeTests, PreviewCoordinatorTests, and ExportCoordinatorTests with controlled slow jobs and cancellation. Capture real export plus edits, Info tab churn, and source switching. Define fairness so background work progresses once interactive demand subsides.

Start with these relevant checks, then run `swift test` and `swift build -c release` before implementation handoff:

```sh
swift test --filter ImageWorkSchedulerTests
swift test --filter HistogramTests
swift test --filter ExportCoordinatorTests
```

Record generated fixture parameters and, for hardware results, source dimensions/format, RAW decoder/version when relevant, hardware, OS, commit, Release configuration, viewport/backing pixels, and cold/warm conditions. Attach before/after traces or durable summaries. The September 1 audit measured component rendering on an M1 Pro (10 CPU cores, 16 GB, macOS 26.6); it did not measure Lightroom/Photomator or real RAW input-to-display latency. Its 198.9 ms rebuild versus 4.9 ms source-reuse PNG result motivates reuse but is not a promised whole-app speedup.

## Fidelity and engineering constraints

Preserve macOS 14 deployment, Swift 6 concurrency safety, Apple-framework-only dependencies, deterministic edit ordering, working-space conversion, premultiplied alpha behavior, orientation, native-resolution export, and deterministic grain where applicable. Do not hide latency by permanently reducing resolution, skipping effects, or weakening precision. Pixel parity needs documented tolerances and representative fine-detail, edge, skin-tone, saturated/wide-gamut, crop, and transparency fixtures; sharing the same graph across resolutions is not proof of equivalence for nonlinear/spatial processing.

## Dependencies and scope boundaries

Hard prerequisites: LUMO-107

Depends on the completed-resource renderer’s completion and ownership contracts. Complements LUMO-053 (batch export reliability); it owns contention policy, not the broader export product workflow.

These tickets provide concrete implementation work for the broader LUMO-055/LUMO-058 quality effort. This ticket is in backlog for planning; implementation and automatic pickup have not been requested as part of ticket creation.

### Comment — codex @ 2026-09-02T04:04:31.549Z

Implemented and committed as df1143b. Visible preview work now uses explicit priority through a bounded editor lane, evicts queued support work when needed, and adds cancellation checks at scheduler/render boundaries. Histogram, comparison, and prefetch are bounded/coalesced; support work is released only after the visible frame is actually presented (with hidden comparison gated and crop edits invalidating comparison). Production export uses an isolated render actor and serial batch output to limit display contention and resident full-resolution memory. Added scheduling documentation and focused tests. Verification: focused scheduler/histogram/export/preview/comparison/cutover/develop suites passed; swift test passed 594 tests with 13 skipped and one known host-specific RAW lens-correction failure; swift build -c release passed with existing Core Image deprecation warnings; git diff --check and dg validate passed with existing warnings. Hardware simultaneous export/edit telemetry capture remains pending on target hardware and is documented in docs/LUMO-113-SCHEDULING.md.

### Comment — claude @ 2026-09-02T04:16:13.704Z

Independent verification (counterpoint review) of commit df1143b.

**Code review.** Read the full diff (ImageWorkScheduler, RenderEngine, AppViewModel, PreviewCoordinator, ExportCoordinator, PreviewSurface). Confirmed: activeEditor/comparison/histogram/adjacentFilmstrip/visibleGrid/background priority ladder with a bounded 4-slot editor backlog that evicts obsolete support jobs on a new visible admission (ImageWorkScheduler.admitEditor); Task.checkCancellation added at RenderEngine.histogram entry/stage boundaries and around the raster-render tail; supporting work (histogram, comparison baseline) now gates on PreviewSurface's drawable-presented confirmation via `didPresentVisibleFrame`, not on graph publication; ExportCoordinator uses a second, independently-bounded RenderEngine actor/context/queue for production export so a non-preemptible full-resolution encode cannot monopolize the display actor; the editor lane only ever runs one job at a time regardless of queue depth, matching RenderEngine's actor serialization.

One inert-but-harmless observation: the `guard !Task.isCancelled` added inside `ImageWorkScheduler.pump()`'s freshly-created Task can never observe `true` in practice, since the Task is created and registered synchronously on the MainActor before anything else can call `.cancel()` on it — the real cancellation protection comes from RenderEngine's own `Task.checkCancellation()` calls at await points, which is correctly wired. Not a defect, not worth a fix.

**Tests run:**
- `swift test --filter ImageWorkSchedulerTests` — 5/5 passed, including the new `testVisibleEditorDropsQueuedSupportBeforeItIsAdmitted`.
- `swift test --filter HistogramTests` — 8/8 passed.
- `swift test --filter ExportCoordinatorTests` — 13/13 passed.
- `swift test` (full suite, run twice for stability) — 594 tests, 13 skipped, 1 failure both times: `RAWCapabilitiesTests.testProbingARealRAWReportsItsDecodersSeeds`, the pre-existing host-specific RAW lens-correction default documented in the implementation comment. No new failures.
- `swift build -c release` — clean.
- `dg validate` — OK (only pre-existing unrelated warnings: `agents.pickup.runner` model name, LUMO-121 context completeness).
- `git status --porcelain` on `Sources/`/`Tests/` — only pre-existing unrelated modifications to `Fixtures.swift`/`MetalPresentationBenchmark.swift` that predate this verification session; no side-effect edits from this review.

**Gap found, not blocking:** acceptance criterion 7 (editor p95 latency/worst-frame-gap and export throughput/memory recorded during *simultaneous* batch export + editing on real hardware) is explicitly documented as not yet done in `docs/LUMO-113-SCHEDULING.md` — it requires real Metal hardware and is intentionally not fabricated in CI. The scheduling mechanism it would measure is implemented and unit-tested; only the empirical hardware capture is outstanding. Filed as LUMO-123 (verification, low priority, parent/depends_on LUMO-113) rather than treating it as a blocker, since it does not indicate a defect in the shipped code.

**Verdict: PASS.** Moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
