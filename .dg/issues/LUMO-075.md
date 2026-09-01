---
id: LUMO-075
title: Settled-frame preview publish still allocates a redundant CGImage/NSImage now that the GPU surface owns display
type: task
status: done
priority: medium
verification_agent: pi
verification_model: openrouter/~deepseek/deepseek-v4-flash-latest
labels:
  - verification
created: 2026-08-31T23:55:54.566Z
updated: 2026-09-01T02:07:29.162Z
order: n
board: product
commits:
  - aa08b38
---

Parent: LUMO-073 (verification follow-up — non-blocking)

## Context

LUMO-073 added a persistent GPU presentation surface (`PreviewSurface`/`PreviewSurfaceView`) that
interactive preview frames now publish through instead of `AppViewModel.previewNSImage`/
`originalPreviewNSImage`. `PreviewView` shows the GPU surface whenever `surface.image != nil`, and
falls back to the `NSImage` only before the surface has ever been populated — once a surface has a
frame, the `NSImage` branch is dead for display purposes.

However, `PreviewCoordinator.render` (`Sources/LumoKit/ViewModels/PreviewCoordinator.swift:214`)
still computes **both** outputs for every settled frame:

```swift
let image = gpuImage == nil || phase == .settled ? await engine.makeCGImage(request) : nil
```

For `phase == .settled`, this calls `engine.makeCGImage(request)` in addition to the
`engine.makeCIImage(request)` call just above it. Both go through `RenderEngine.buildImage`
(rebuilding the CI graph a second time), and `makeCGImage` additionally does a real
`CIContext.createCGImage` rasterization — a second GPU render pass whose only consumer
(`previewNSImage`/`originalPreviewNSImage` in `AppViewModel`) is no longer shown once the surface is
active.

## Ask

Stop computing the CGImage/NSImage side for settled frames once the GPU surface is the active
display path, or confirm a concrete remaining consumer of `previewNSImage`/`originalPreviewNSImage`
(accessibility, export preview, etc.) and narrow the redundant render to only when that consumer is
actually needed. `grep -rn "previewNSImage\|originalPreviewNSImage" Sources/` currently shows no
consumer besides `PreviewView`'s now-dead fallback branch and the `AppViewModel` properties
themselves.

Filed as backlog, not blocking: it is a real duplicate GPU render pass on every settled frame (drag
release, slider commit), not a correctness break — LUMO-073 verification confirmed the GPU surface
itself displays correctly and interactive frames already skip this path.


### Comment — codex @ 2026-09-01T01:13:41.579Z

Implemented in aa08b38. PreviewCoordinator now falls back to makeCGImage only when makeCIImage returns nil, eliminating the redundant settled-frame graph rebuild/raster pass for GPU-backed previews. Added regression coverage for the GPU path and updated real-engine pixel tests to verify the PreviewSurface contract. Verification: swift test (428 passed, 24 expected skips), swift build -c release, git diff --check, dg validate (known warnings only).


### Comment — pi @ 2026-09-01T02:07:25.681Z

Verification report (pi, LUMO-075) — PASS

Verdict: verified. The redundant settled-frame rasterization is gone; no correctness, security, or new-performance regression found. No localized fixes required.

Checks run (all green):
- swift test — 429 tests, 24 skipped, 0 failures (matches the 428+1 claimed by the implementation)
- swift build -c release — clean
- swift build (forced recompile of touched files) — only pre-existing CIKernel-deprecation warnings in RenderPipeline.swift / ToneCurveFilterCache.swift, both untouched by aa08b38 (present on parent 41c99cf)
- git diff --check — clean
- dg validate — OK (2 unrelated known warnings: codex runner model, LUMO-076 context completeness)

Correctness review:
- PreviewCoordinator.render now rasterizes only when makeCIImage returns nil, for both phases. Settled GPU frames no longer rebuild the CI graph a second time or call CIContext.createCGImage; the surface owns display.
- publishPreview preserves all settled-phase side effects via its else branch: updateHistogram() and pendingDevelopChange -> scheduleOriginalPreview() still fire per settled GPU publication; only the now-dead previewNSImage assignment is skipped.
- Failure semantics unchanged: onFailure still fires iff both gpuImage and image are nil.
- Raster seam preserved for non-GPU conformers/test doubles: RenderEngining's default makeCGImage (over render(request)) is reached when makeCIImage returns nil, exercised by the existing ControlledRenderEngine tests; conditioned behavior identical before/after for that path.
- Consumer audit: grep across Sources/ and Tests/ confirms previewNSImage/originalPreviewNSImage are read only by PreviewView's fallback branches (unreachable once the surface is populated) and by AppViewModel itself; export uses its own render() -> RenderResult path.
- New regression test asserts the contract directly: settled GPU publication carries gpuImage != nil, image == nil, zero makeCGImage calls. Real-engine pixel tests were re-pointed at previewSurface.image.

Security: N/A — no new surface; Swift 6 mode compiles with zero new diagnostics (no @unchecked Sendable / nonisolated(unsafe) introduced).

Performance: second GPU render pass + duplicate graph build eliminated per settled frame (drag release, slider commit).

Non-blocking findings:
- LUMO-078 (backlog child, verification label, parent LUMO-075): the main-preview NSImage fallback path (PreviewView fallback branches, AppViewModel previewNSImage/originalPreviewNSImage publishing) is permanently dead once a surface has ever presented; consider removing or re-scoping to a documented seam.
- Observation only (pre-existing from LUMO-073, not introduced here): if makeCIImage ever returned nil while makeCGImage succeeded, publishPreview would leave a stale surface frame visible while setting the NSImage — a non-issue on the real engine (both go through buildImage), but worth a comment if the seam survives.

Verification commits: none (review only; no source changes made).

## Agent log

- 2026-09-01T02:07:29.160Z: Verified: settled GPU previews no longer rasterize a redundant CGImage; tests 429/24-skip green, release build clean, dg validate OK. Non-blocking follow-up tracked as LUMO-078.
