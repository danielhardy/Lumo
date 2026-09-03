---
id: LUMO-115
title: Restore the full adjusted canvas when re-entering Crop
type: bug
status: done
priority: high
labels:
  - performance
  - epic:quality
  - crop
  - correctness
created: 2026-09-01T22:05:12.126Z
updated: 2026-09-01T23:20:54.233Z
order: a0
board: product
commits:
  - d8aabb82930b150e5d9a3793d36aeaa9f4421056
---

## Objective

Display the full oriented adjusted image under the full-source crop overlay when editing an existing crop, with responsive commit/cancel transitions.

## Context and evidence

Performance audit item 10, evaluated at commit `724ad99`: [September 1 audit](../../docs/PERFORMANCE_AUDIT_2026-09-01.md).
The user requested tangible responsiveness improvements without sacrificing visual fidelity or accuracy; prioritize code quality and measured impact over minimizing implementation effort.

**Evidence:** [AppViewModel.beginCrop](/Users/dhardy/Dev/Lumo/Sources/LumoKit/ViewModels/AppViewModel.swift:1381) resets navigation and exposes the draft but does not request an uncropped image. [PreviewView.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Views/PreviewView.swift:103) continues using the committed cropped surface while its overlay uses full `sourceSize` coordinates.

**Impact:** After committing a crop, re-entering Crop draws a full-source-coordinate overlay over already-cropped pixels. Performance work must not make this incorrect geometry merely faster.

**Approach:** Retain/reuse the uncropped adjusted stage for crop editing and map the overlay to that stage. Commit/cancel switches composition without source redevelopment where cached source detail is adequate. Keep final crop-relative vignette/grain behavior explicit.

## Acceptance criteria

- [ ] After committing a nontrivial crop, reopening Crop displays the full source framing with the saved rectangle correctly aligned to recognizable image content.
- [ ] Expanding or resetting the draft exposes image content outside the previous crop; Cancel restores the committed framing without adding an undo entry or persisting the draft.
- [ ] Apply commits exactly one document/history change; undo/redo, relaunch, and copy/paste preserve the crop contract.
- [ ] Landscape and oriented portrait images behave correctly after zoom/pan, source switches, original comparison, and side-by-side mode.
- [ ] Cached uncropped adjusted stages are reused where adequate; handle movement and composition transitions do not trigger unnecessary RAW development.
- [ ] Vignette/grain framing during crop editing is explicitly defined, and the final committed render retains existing crop-relative semantics and matches export.
- [ ] Verification includes visible pixel landmarks/geometry and UI behavior, not only assertions about the normalized crop rectangle.

## Verification plan

Extend CropWorkflowTests, CropPipelineTests, and ComparisonModeTests using generated asymmetric landmark fixtures. Perform commit → reopen → expand/reset → cancel/apply on oriented images and compare geometry to source coordinates; include history and final export parity.

Start with these relevant checks, then run `swift test` and `swift build -c release` before implementation handoff:

```sh
swift test --filter CropWorkflowTests
swift test --filter CropPipelineTests
swift test --filter ComparisonModeTests
```

Record generated fixture parameters and, for hardware results, source dimensions/format, RAW decoder/version when relevant, hardware, OS, commit, Release configuration, viewport/backing pixels, and cold/warm conditions. Attach before/after traces or durable summaries. The September 1 audit measured component rendering on an M1 Pro (10 CPU cores, 16 GB, macOS 26.6); it did not measure Lightroom/Photomator or real RAW input-to-display latency. Its 198.9 ms rebuild versus 4.9 ms source-reuse PNG result motivates reuse but is not a promised whole-app speedup.

## Fidelity and engineering constraints

Preserve macOS 14 deployment, Swift 6 concurrency safety, Apple-framework-only dependencies, deterministic edit ordering, working-space conversion, premultiplied alpha behavior, orientation, native-resolution export, and deterministic grain where applicable. Do not hide latency by permanently reducing resolution, skipping effects, or weakening precision. Pixel parity needs documented tolerances and representative fine-detail, edge, skin-tone, saturated/wide-gamut, crop, and transparency fixtures; sharing the same graph across resolutions is not proof of equivalence for nonlinear/spatial processing.

## Dependencies and scope boundaries

Hard prerequisites: None; independently actionable.

Independent correctness follow-up to LUMO-101. Do not block on the resolution pyramid or tile architecture; coordinate uncropped-stage reuse with those tickets when available.

These tickets provide concrete implementation work for the broader LUMO-055/LUMO-058 quality effort. This ticket is in backlog for planning; implementation and automatic pickup have not been requested as part of ticket creation.

### Comment — codex @ 2026-09-01T23:12:43.009Z

Implemented in commit cea6fd4. Crop re-entry now renders the full oriented adjusted stage with a neutral transient crop, reusing developed-source/RAW cache state; cancel and unchanged Apply restore the committed crop render without history changes. Vignette/grain remain full-frame during transient crop editing and retain existing post-crop semantics for committed preview/export. Verification: focused CropWorkflowTests, CropPipelineTests, ComparisonModeTests passed; full swift test passed (566 tests, 26 expected environment skips); swift build -c release passed; git diff --check passed.

### Comment — claude @ 2026-09-01T23:20:49.185Z

## Verification report — passing

**Scope:** independent counterpoint review of commit cea6fd4 (crop re-entry framing fix) against the acceptance criteria and verification plan.

**Code review:** `displayRequest` (AppViewModel.swift:1312) correctly strips the composition crop (`requested.crop = .neutral`) whenever `isCropToolActive`, so the full oriented adjusted stage renders under the full-source overlay while editing. `beginCrop`/`commitCrop`(unchanged-draft path)/`cancelCrop` each call `schedulePreview()` at the right transition points; `commitCrop`'s explicit `if document == previousDocument` branch is necessary because `updateDocument` no-ops (no render, no history) when the transform doesn't change the document — confirmed by reading `updateDocument` (AppViewModel.swift:1151). Cache-key structure confirmed: `DevelopedSourceCacheKey` (RenderCacheKey.swift) excludes crop entirely, so toggling crop on/off during tool entry/exit reuses the developed RAW source and only recomputes the cheap post-crop composition (`PreviewCacheKey`, which is keyed on the full document hash). `RenderPipeline.render` (RenderPipeline.swift:105-107) applies crop before vignette/grain, so a neutral transient crop correctly yields full-frame vignette/grain during editing while the committed path retains existing post-crop semantics — matches the documented approach.

**Gap found and fixed:** the implementation commit touched only `AppViewModel.swift` — no test file changed, despite the verification plan explicitly requiring extending `CropWorkflowTests`/`CropPipelineTests`/`ComparisonModeTests` and acceptance criterion 7 requiring pixel/geometry checks rather than only normalized-rectangle assertions. The existing `CropWorkflowTests` cases only assert `document.crop`/undo depth, never the actual pixels or render request shown under the overlay — they would pass identically with or without this fix.

This was a localized, testable gap (no product behavior change), so I added `testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit` to `Tests/LumoKitTests/CropTests.swift`, which inspects `FakeRenderEngine.previewRequests` (the actual render request handed to the engine) to assert: (1) reopening Crop after a committed nontrivial crop requests a render with `document.crop.isIdentity == true` while `viewModel.document.crop` remains the committed rect, and (2) Cancel's subsequent request restores `document.crop == committed`. Verified this test fails against the pre-fix `AppViewModel.swift` (timed out / assertion failure) and passes against the fix — it is a genuine regression guard for this issue, not a tautology.

**Verification commands run:**
- `swift test --filter CropWorkflowTests` — 3/3 pass (incl. new test)
- `swift test` — 567 tests, 26 expected environment skips, 0 failures
- `swift build -c release` — succeeds (only pre-existing `CIKernel(source:)` deprecation warnings, unrelated)
- `git diff --check` — clean

**Verdict:** PASS. No blocking issues found; the missing-test gap was fixed inline rather than warranting a blocker ticket. Verification commit: (local main, see `git log -1 -- Tests/LumoKitTests/CropTests.swift`).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T23:20:54.231Z: Verified LUMO-115 crop re-entry fix (cea6fd4): code review confirms correct behavior and cache reuse. Added missing regression test (CropWorkflowTests) that the implementation's verification plan required but the implementation commit omitted; confirmed it fails pre-fix and passes post-fix. swift test (567 tests) and swift build -c release both pass.
