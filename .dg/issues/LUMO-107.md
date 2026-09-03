---
id: LUMO-107
title: Separate completed GPU image rendering from canvas presentation
type: task
status: done
priority: high
labels:
  - performance
  - epic:quality
  - rendering
  - live-preview
created: 2026-09-01T22:05:09.766Z
updated: 2026-09-02T02:26:03.600Z
depends_on:
  - LUMO-114
order: a0
board: product
commits:
  - "3195e55"
---

## Objective

Make warm canvas movement a cheap transform of completed GPU pixels while expensive source/adjustment rendering runs outside the main actor.

## Context and evidence

Performance audit item 2, evaluated at commit `724ad99`: [September 1 audit](../../docs/PERFORMANCE_AUDIT_2026-09-01.md).
The user requested tangible responsiveness improvements without sacrificing visual fidelity or accuracy; prioritize code quality and measured impact over minimizing implementation effort.

**Evidence:** [RenderEngine.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderEngine.swift:140) returns a graph from `makeCIImage`. [PreviewSurface.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Views/PreviewSurface.swift:210) calls `context.render` inside the `@MainActor` MTKView coordinator. Navigation transforms that graph and submits it again. The actor method finishing therefore does not mean image processing finished. GPU execution is asynchronous, but graph evaluation/encoding and drawable acquisition still occur on the UI path.

**Impact:** Expensive adjustments, first-use kernels, or source evaluation can delay input handling. Pan/zoom has no explicit guarantee of sampling already-completed image pixels; Core Image may reuse intermediates, but the application does not own that guarantee.

**Approach:** Render off the main actor into reusable GPU textures or IOSurfaces, then present completed resources with a small transform/compositing pass. Preserve revision ownership and retain the last valid frame. Connect latest-request scheduling to actual processing completion, rather than just graph construction. Define context/device/queue ownership explicitly; the engine currently has a separate context from its static presentation context despite comments describing one context.

**Fidelity:** Keep color management, alpha semantics, and adequate intermediate precision. Do not bake processing stages into RGBA8 merely to obtain a texture. Avoid CPU readback. Preserve strict Swift concurrency rather than adding unchecked sharing of mutable filters.

## Acceptance criteria

- [ ] Pan, fit, fill, and zoom within available rendered detail perform no source development or adjustment evaluation.
- [ ] Expensive graph evaluation/encoding runs off the main actor; UI-owned drawable acquisition and presentation have explicit measured budgets.
- [ ] The scheduler bounds processing and presentation submissions, retains only the newest pending request, and uses actual completion rather than graph construction as its pacing boundary.
- [ ] Source switches, superseded revisions, missing drawables, GPU failure, and resource eviction retain a valid frame and cannot publish a stale source or reuse an in-flight texture unsafely.
- [ ] Color-managed results match the reference renderer within a documented precision tolerance; no intermediate RGBA8 bake, CPU readback, or lossy encoding is introduced.
- [ ] On the reference 60 Hz display, warm transforms target the next refresh and p95 input-to-present is ≤33 ms; ordinary adjustments target ≤33 ms and release-to-settled ≤200 ms with separate CPU/GPU/presentation measurements.

## Verification plan

Extend PreviewSurfaceTests, PreviewCoordinatorTests, and pixel parity coverage. Capture real MTKView rendering during heavy effects, source replacement, resize, and sustained pan/zoom. Exercise texture lifetime and failed-command-buffer recovery. Measure drawable acquisition separately from CI graph evaluation.

Start with these relevant checks, then run `swift test` and `swift build -c release` before implementation handoff:

```sh
swift test --filter PreviewSurfaceTests
swift test --filter PreviewCoordinatorTests
swift build -c release
```

Record generated fixture parameters and, for hardware results, source dimensions/format, RAW decoder/version when relevant, hardware, OS, commit, Release configuration, viewport/backing pixels, and cold/warm conditions. Attach before/after traces or durable summaries. The September 1 audit measured component rendering on an M1 Pro (10 CPU cores, 16 GB, macOS 26.6); it did not measure Lightroom/Photomator or real RAW input-to-display latency. Its 198.9 ms rebuild versus 4.9 ms source-reuse PNG result motivates reuse but is not a promised whole-app speedup.

## Fidelity and engineering constraints

Preserve macOS 14 deployment, Swift 6 concurrency safety, Apple-framework-only dependencies, deterministic edit ordering, working-space conversion, premultiplied alpha behavior, orientation, native-resolution export, and deterministic grain where applicable. Do not hide latency by permanently reducing resolution, skipping effects, or weakening precision. Pixel parity needs documented tolerances and representative fine-detail, edge, skin-tone, saturated/wide-gamut, crop, and transparency fixtures; sharing the same graph across resolutions is not proof of equivalence for nonlinear/spatial processing.

## Dependencies and scope boundaries

Hard prerequisites: LUMO-114

Depends on telemetry corrections for trustworthy completion measurements. Owns render/presentation resource boundaries; coordinate with the resolution pyramid and processing-prefix cache tickets. It does not own catalog persistence or document semantics.

These tickets provide concrete implementation work for the broader LUMO-055/LUMO-058 quality effort. This ticket is in backlog for planning; implementation and automatic pickup have not been requested as part of ticket creation.

### Comment — codex @ 2026-09-02T02:05:32.902Z

Implemented in commit 3195e55. RenderEngine now evaluates preview graphs off-main into completed, color-managed RGBA16Float Metal textures with explicit processing queue ownership; PreviewSurface applies only transform/compositing and keeps one presentation submission in flight. Added RAW/GPU parity coverage and presentation timing telemetry (drawable acquisition, encoding, GPU completion, drawable presentation). Verification: focused LUMO-107 tests pass; swift build -c release passes; full swift test passes all LUMO-107 coverage but retains one pre-existing host-specific RAWCapabilities lensCorrectionEnabled seed assertion.

### Comment — claude @ 2026-09-02T02:26:00.290Z

Counterpoint verification (independent re-review of the codex implementation, commit 3195e55), HEAD 3195e55.

PASS — implementation is sound; commits code-level acceptance criteria, one non-blocking follow-up filed.

Reviewed:
- RenderEngine.makeCIImage now renders into an actor-owned RGBA16Float `.private`-storage Metal texture on its own command queue, awaits GPU completion via `commitAndWaitForCompletion` before returning, and only hands back a CIImage once the write is confirmed complete — no lazy graph crosses the actor boundary on the production (device-present) path, no CPU readback, no RGBA8 bake.
- PreviewSurfaceView.Coordinator.draw() only applies navigation transform + letterbox composite to the already-completed image; it never calls into RenderEngine. Confirmed structurally that pan/fit/fill/zoom cannot trigger source/adjustment evaluation.
- Presentation and processing contexts/queues are explicitly separate (`RenderEngine.presentationContext`/`presentationQueue` on `@MainActor`, `context`/`commandQueue` inside the actor), sharing only the `MTLDevice`, matching the ticket's "define ownership explicitly" ask. `RenderStackTests` still caps the module at two `CIContext` owners.
- Failure/staleness handling: `PreviewSurface.rejectPresentation`/`markPresentationSucceeded` retain `lastValidImage`/`lastValidSpace` on a failed command buffer without poisoning it with a stale candidate; `clear()` invalidates telemetry association on source switch; `PreviewCoordinator.isCurrent(token)` drops superseded revisions. Covered by `testAFailedReplacementKeepsTheLastValidFrame` and `testAStalePresentationCompletionCannotCommitOverANewerFrame`.
- Scheduler (`PreviewCoordinator`) already retained only the newest pending request pre-3195e55; this commit changes its pacing boundary to actual GPU completion (via the now-awaited `makeCIImage`) rather than graph construction, satisfying that acceptance line.
- Pixel parity: new `testDisplayPreviewIsBackedByACompletedMetalTexture` and `testCompletedRAWPreviewReflectsDevelopSettings` assert the completed-texture path matches the actor-owned raster path and reflects RAW develop settings; `RenderStackTests`/`RenderPipelineTests` parity suites unaffected.

Checks run:
- `swift test --filter PreviewSurfaceTests` — 4/4 pass.
- `swift test --filter PreviewCoordinatorTests` — 6/6 pass, 1 opt-in benchmark skipped (LUMO_BENCH unset, expected).
- `swift test` (full suite) — 576 tests, 0 failures, 30 skipped, on HEAD with the working tree's unrelated uncommitted local RAW fixture (`Tests/LumoKitTests/Fixtures.swift`, `realworldtest/`) temporarily stashed. With that fixture present, three unrelated pre-existing tests fail/skip differently (`CropWorkflowTests.testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit`, `ImageSourceTests.testRAWBytesAreDetectedWithoutAFilename`, `RAWCapabilitiesTests.testProbingARealRAWReportsItsDecodersSeeds`) — confirmed unrelated to this ticket's changes by reproducing the same failures on the pre-3195e55 parent commit in a scratch worktree once the same local RAW fixture is present; none touch RenderEngine/PreviewSurface/PreviewCoordinator code paths. Not treated as blockers for LUMO-107.
- `swift build -c release` — succeeds (pre-existing CIKernel deprecation warnings only, unrelated to this change).

Gap (non-blocking, filed as follow-up): LUMO-107's own acceptance criterion 6 (p95 input-to-present ≤33 ms warm/ordinary, ≤200 ms release-to-settled, measured on the reference 60 Hz display) has no hardware capture taken after this commit. The only archived capture (`docs/LUMO-118-DSC07826-...-summary.md`, p95 35.966 ms) predates 3195e55 and exercised the old lazy-graph presentation path, so it cannot confirm or refute this ticket's target. Per the LUMO-118/LUMO-119 precedent (measurement requires a human-operated session with a real display; explicitly does not block completion of the ticket it measures), filed LUMO-121 (priority medium, label verification, non-blocking) to capture that evidence on a commit at or after 3195e55.

No code changes made during this verification pass.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T02:26:03.598Z: Counterpoint verification passed: focused + full test suites and release build green; architecture/failure-path review clean; filed non-blocking LUMO-121 for post-change hardware latency capture.
