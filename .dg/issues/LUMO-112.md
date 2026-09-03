---
id: LUMO-112
title: Isolate canvas and crop interaction from broad SwiftUI observation
type: task
status: done
priority: medium
labels:
  - performance
  - epic:quality
  - swiftui
  - zoom
  - crop
created: 2026-09-01T22:05:11.273Z
updated: 2026-09-02T03:46:13.026Z
depends_on:
  - LUMO-114
order: z3
board: product
commits:
  - "6e79290"
---

## Objective

Keep pointer-frequency navigation and crop changes local to the affected views rather than invalidating unrelated editor UI.

## Context and evidence

Performance audit item 7, evaluated at commit `724ad99`: [September 1 audit](../../docs/PERFORMANCE_AUDIT_2026-09-01.md).
The user requested tangible responsiveness improvements without sacrificing visual fidelity or accuracy; prioritize code quality and measured impact over minimizing implementation effort.

**Evidence:** [PreviewView.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Views/PreviewView.swift:6) and the surrounding editor observe the broad AppViewModel. Navigation and crop draft mutations are published there. `PreviewSurface` already isolates image publication, but not pointer-frequency navigation/document/draft updates.

**Approach:** Introduce narrowly observed canvas/crop state and inspector state. Let transform and handle movement update their own view subtree. Keep document history and persistence at clear commit/checkpoint boundaries. Use SwiftUI profiling to identify expensive invalidations rather than migrating frameworks solely on assumption.

## Acceptance criteria

- [ ] Pan, zoom, and crop-handle events do not cause unrelated browser, filmstrip, or inspector view bodies to reevaluate solely because shared AppViewModel published interaction state.
- [ ] Canvas/crop state has clear narrow observation and ownership, with document state, undo grouping, and persistence semantics preserved.
- [ ] Pointer responsiveness remains correct for wheel, pinch, drag, keyboard navigation, fit/fill, side-by-side, and accessibility actions.
- [ ] Source switching and gesture cancellation reset transient state without leaking crop/navigation state between photos.
- [ ] Before/after SwiftUI and Time Profiler captures report body evaluations, main-thread time, allocations, and input-to-display/frame gaps for the same interactions.
- [ ] Framework or view-model migrations are justified by the measured invalidation graph; public-facing behavior and selection are unchanged.

## Verification plan

Exercise CanvasNavigationTests, CropWorkflowTests, ComparisonModeTests, and keyboard tests; add coverage only for new ownership/lifecycle failure modes. Use actual view profiling to verify unrelated subtree invalidation, which model tests cannot establish.

Start with these relevant checks, then run `swift test` and `swift build -c release` before implementation handoff:

```sh
swift test --filter CanvasNavigationTests
swift test --filter CropWorkflowTests
swift test --filter ComparisonModeTests
```

Record generated fixture parameters and, for hardware results, source dimensions/format, RAW decoder/version when relevant, hardware, OS, commit, Release configuration, viewport/backing pixels, and cold/warm conditions. Attach before/after traces or durable summaries. The September 1 audit measured component rendering on an M1 Pro (10 CPU cores, 16 GB, macOS 26.6); it did not measure Lightroom/Photomator or real RAW input-to-display latency. Its 198.9 ms rebuild versus 4.9 ms source-reuse PNG result motivates reuse but is not a promised whole-app speedup.

## Fidelity and engineering constraints

Preserve macOS 14 deployment, Swift 6 concurrency safety, Apple-framework-only dependencies, deterministic edit ordering, working-space conversion, premultiplied alpha behavior, orientation, native-resolution export, and deterministic grain where applicable. Do not hide latency by permanently reducing resolution, skipping effects, or weakening precision. Pixel parity needs documented tolerances and representative fine-detail, edge, skin-tone, saturated/wide-gamut, crop, and transparency fixtures; sharing the same graph across resolutions is not proof of equivalence for nonlinear/spatial processing.

## Dependencies and scope boundaries

Hard prerequisites: LUMO-114

Depends on cheap representative telemetry for before/after evidence. Can proceed independently of texture and tile implementation; align on the public canvas-state boundary first.

These tickets provide concrete implementation work for the broader LUMO-055/LUMO-058 quality effort. This ticket is in backlog for planning; implementation and automatic pickup have not been requested as part of ticket creation.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T03:46:13.021Z: Implemented narrow CanvasInteractionState and InspectorState observation boundaries. Pan/zoom, crop drafts, and inspector chrome no longer publish through AppViewModel; committed crop/history/persistence and render behavior remain in AppViewModel. Added publisher-isolation and source-reset regressions plus docs/CANVAS_OBSERVATION_PERFORMANCE.md. Verification: focused canvas/crop/comparison suites pass; swift build -c release passes; full swift test has 592 tests, 13 expected skips, and one pre-existing host-specific RAWCapabilities lensCorrectionEnabled seed failure; dg validate passes with existing warnings.
