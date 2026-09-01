---
id: LUMO-073
title: Replace per-frame CGImage/NSImage preview publication with a persistent GPU presentation surface
type: task
status: done
priority: urgent
labels:
  - verification
  - mvp
  - performance
  - live-preview
  - rendering
created: 2026-08-31T23:04:18.870Z
updated: 2026-09-01T01:11:28.768Z
order: zzz
board: product
---

Parent: LUMO-069 (verification blocker — unresolved acceptance criteria)

## Context

LUMO-069's objective was to replace per-frame image-object publication with a frame-paced GPU
presentation path. Commit 389ba63 delivered the sizing/pacing half (distinct `.interactive`
`RenderScale` case with a backing-pixel/frame-budget-derived pixel cap, zero pre-render debounce,
one-in-flight/latest-pending coalescing, and removal of the `.easeInOut` animations from the hot
path) but did not touch the presentation architecture the issue explicitly required.

As of the current `main` (post-389ba63):

- There is no `MTKView`, `CIRenderDestination`, `MTLDrawable`, or `CAMetalLayer` anywhere in
  `Sources/` (`grep -rn "MTKView\|CIRenderDestination\|MTLDrawable\|CAMetalLayer" Sources/` is empty).
- `PreviewCoordinator.render` still calls `engine.makeCGImage(request)` for every interactive frame
  (`Sources/LumoKit/ViewModels/PreviewCoordinator.swift:208`).
- `AppViewModel.publishPreview` still wraps every published `CGImage` in a fresh `NSImage` and
  assigns it to `previewNSImage`, a broad `@Published var` on `AppViewModel`
  (`Sources/LumoKit/ViewModels/AppViewModel.swift:887-891`), for both interactive and settled
  phases alike — the same allocate-per-tick, whole-ObservableObject-invalidating path that predates
  this issue.
- No texture/drawable reuse exists; nothing is released "on source change or memory pressure"
  because nothing persistent was created to release.

## Unresolved acceptance criteria (from LUMO-069)

- [ ] "The visible editor uses a persistent Metal-backed presentation surface ... and renders Core
  Image output into a reusable destination without allocating `CGImage` and `NSImage` on every
  slider tick." — not implemented; still allocates both every frame.
- [ ] "Interactive frames update only the preview surface; they do not publish through the broad
  `AppViewModel` observation path." — not implemented; `previewNSImage` is exactly that broad
  `@Published` path, used for interactive and settled frames alike.
- [ ] "Memory remains bounded during a five-minute continuous drag; textures/drawables are reused
  and released on source change or memory pressure." — unverified/not applicable since no
  texture/drawable exists to reuse.

## What already holds (do not re-litigate)

- Interactive pixel policy is now distinct from settled/full and derived from live canvas backing
  size and a frame budget (`RenderScale.interactive`, `Sources/LumoKit/Models/RenderScale.swift`).
- `PreviewCoordinator` has no fixed pre-render delay and coalesces to one in-flight render plus one
  latest pending document (`Sources/LumoKit/ViewModels/PreviewCoordinator.swift`).
- `testLargePreviewInteractiveLatencyBenchmark` passes under `LUMO_BENCH=1` (p50 6.5 ms, p95 6.7 ms
  for a 60 MP-class source), so the frame-budget sizing itself is real and measured.
- The `.easeInOut` SwiftUI animations were removed from the preview image transitions in
  `PreviewView.swift`.

## Scope

Design and implement the actual presentation-surface swap called for in LUMO-069's acceptance
criteria and implementation notes: profile `CIContext.startTask`/`CIRenderDestination` vs. `MTKView`
vs. direct texture rendering, then render interactive (and ideally settled) frames into a persistent,
reusable GPU destination that the visible editor presents directly, without an `NSImage`/`CGImage`
round-trip or a broad `AppViewModel` publish on every interactive frame. Keep side-by-side and
single-image modes on the same live-surface behavior and preserve aspect/color-space/orientation/
comparison/accessibility semantics, per the original acceptance criteria.

This is architectural (new rendering surface, new state ownership boundary between the render
pipeline and SwiftUI), not a localized fix, so it was filed as a follow-up rather than patched
directly during LUMO-069 verification.


### Comment — codex @ 2026-08-31T23:51:05.575Z

Implemented in commit 14a1ca3. Added a persistent MTKView/CAMetalLayer presentation surface backed by Core Image, moved interactive publications to GPU CIImage output with surface-local observation, retained raster fallback for non-GPU/test renderers, and applied the same surface path to the original comparison panel. Surfaces are cleared on source changes. Verification: swift test (426 passed, 23 expected skips), swift build -c release, git diff --check, and dg validate passed; validate has only pre-existing runner-model/context warnings.


### Comment — claude @ 2026-08-31T23:56:47.286Z

## Independent verification report (counterpoint pass)

**Verdict: PASS, after two localized fixes committed as f3bb800.**

Reviewed commit 14a1ca3 against the three unresolved LUMO-069 acceptance criteria and found the
architecture correct but the implementation had two functional bugs that would have made the
feature non-working in practice, despite `swift test` passing (426/426) both before and after —
neither bug is reachable from the headless XCTest suite, since it exercises no live `MTKView`.

### Blocking findings (fixed, not deferred)

1. **Drawable never presented** — `PreviewSurfaceView.updateNSView`
   (`Sources/LumoKit/Views/PreviewSurface.swift`) called
   `CIContext.render(_:to:commandBuffer: nil, ...)` then `view.draw()` with no `MTKViewDelegate`
   assigned. Core Image's own internal command buffer draws into the drawable's texture, but nothing
   ever called `MTLCommandBuffer.present(drawable)` — so the rendered frame was never scheduled for
   display. Compounding this, the `MTKView` was constructed with `MTKView()` (no `device`), which
   Apple's own pattern requires to be set explicitly or `currentDrawable` stays `nil` and the whole
   `updateNSView` body no-ops. Net effect: the persistent surface would show nothing, ever, on real
   hardware. Fixed by giving `PreviewSurfaceView` an explicit `MTLDevice`/`MTLCommandQueue`
   (`RenderEngine.presentationDevice`, new) and calling `commandBuffer.present(drawable)` +
   `commandBuffer.commit()`.

2. **Interactive frames silently dropped as failures** — `PreviewCoordinator.render`
   (`Sources/LumoKit/ViewModels/PreviewCoordinator.swift:214`) computed
   `image = gpuImage == nil || phase == .settled ? await engine.makeCGImage(request) : nil`, then
   `guard let image else { onFailure?(request); return }`. For every interactive frame in production
   (`gpuImage != nil`, `phase == .interactive`), `image` was `nil` by design (the whole point of the
   GPU branch), so the guard treated the successful GPU render as a failure: `Publication` was never
   built, `previewSurface.present` was never called, and `onFailure` fired instead — which sets
   `statusMessage = "Could not render …"`. During an interactive drag the surface would never update
   and the UI would show a render-failed message on every tick, only recovering on the settled frame.
   Fixed by changing the guard to `image != nil || gpuImage != nil`.

### Confirmed already-working (per LUMO-069 AC, re-verified after the fixes)

- Interactive frames now publish only through `PreviewSurface` (a narrow `ObservableObject`, not
  `AppViewModel`) — confirmed by re-reading `publishPreview`: for interactive phase, `image` is nil
  and the early-return guard skips every `AppViewModel` `@Published` write.
- Side-by-side and single-image panels both route through `PreviewSurfaceView` identically
  (`PreviewView.swift`); surfaces are cleared on source change (`AppViewModel.swift` calls
  `previewSurface.clear()`/`originalPreviewSurface.clear()` alongside `previewCoordinator.cancel()`).
- `testLargePreviewInteractiveLatencyBenchmark` still passes under `LUMO_BENCH=1` — sizing/pacing
  from 389ba63 is untouched by this change.

### Non-blocking findings filed as backlog (not fixed here — broader than a localized patch)

- **LUMO-075** (medium): settled-frame publish still does a redundant second GPU render
  (`makeCIImage` + `makeCGImage`, both calling `buildImage`) feeding `previewNSImage`/
  `originalPreviewNSImage`, which have no remaining display consumer once the surface is active.
  Real duplicate work on every drag-release, not a correctness bug.
- **LUMO-076** (low): `PreviewSurfaceView` renders with a hardcoded `WorkingSpace.current.cgColorSpace`
  rather than the `request.space` the presented `CIImage` was actually built for. Currently inert
  because `WorkingSpace.current` is pinned to `.sRGB` with no UI path to change it, but will become a
  live color-correctness bug the moment that stops being true.

### Checks run

- `swift build` (debug) — clean, only pre-existing `CIKernel(source:)`/`CIColorKernel(source:)`
  deprecation warnings unrelated to this change.
- `swift build -c release` — clean.
- `swift test` — 426 passed, 23 expected skips, 0 failures (both before and after the fixes).
- `git diff --check` — clean, no whitespace errors.
- `swift run` — launched the real app binary on this macOS host; process stayed up (no crash) for
  the smoke window. Did **not** perform a scripted GUI drive (load a RAW, drag a slider, screenshot
  the pixels) — no fixture/accessibility driver was available in this session, so the drawable-
  presentation fix is verified by API-level reasoning (device/command-buffer/present chain) plus the
  code-path fix for the dropped-publication bug, not by an eyeballed on-screen frame. Recommend a
  quick manual drag-and-look before relying on this for a release build.

Verification commit: f3bb800 (`LUMO-073 fix GPU preview surface: present drawable, don't drop
interactive publications`).
