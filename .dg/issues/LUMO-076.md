---
id: LUMO-076
title: PreviewSurfaceView hardcodes sRGB for GPU presentation instead of the request's WorkingSpace
type: task
status: done
priority: low
verification_agent: pi
verification_model: openrouter/~deepseek/deepseek-v4-flash-latest
labels:
  - verification
created: 2026-08-31T23:55:56.514Z
updated: 2026-09-01T02:32:57.040Z
order: a0
board: product
---

Parent: LUMO-073 (verification follow-up — non-blocking)

## Context

`PreviewSurfaceView.updateNSView` (`Sources/LumoKit/Views/PreviewSurface.swift`) renders the GPU
presentation surface with a hardcoded color space:

```swift
let colorSpace = WorkingSpace.current.cgColorSpace
```

(post-verification-fix; originally `CGColorSpace(name: CGColorSpace.sRGB)!` hardcoded directly).
Either way this ignores the actual `request.space` that produced the `CIImage` being presented —
every other raster path in the render stack (`RenderEngine.makeCGImage`,
`Sources/LumoKit/Models/RenderEngine.swift:229`) uses `request.space.cgColorSpace` instead.

## Why this isn't blocking today

`WorkingSpace.current` is a `static let` pinned to `.sRGB`
(`Sources/LumoKit/Models/WorkingSpace.swift:49`) — there is no UI path that switches working space
yet, so today `WorkingSpace.current` and `request.space` are always the same value in practice. The
hardcoding is inert, not a live display bug.

## Ask

`PreviewSurface`/`PreviewSurfaceView` doesn't currently carry the `WorkingSpace` the presented
`CIImage` was rendered in. Thread it through (e.g. `PreviewSurface.present(_:space:)`) so the GPU
surface renders in the color space it was actually asked for, the same way the CGImage path does —
otherwise this becomes a live color-correctness bug the moment `WorkingSpace.current` stops being a
constant (the comment at `WorkingSpace.swift:47` calls the P3 switch out as a real future change).


### Comment — codex @ 2026-09-01T02:30:35.798Z

Implemented in commit 2d8394a. PreviewSurface now stores the WorkingSpace associated with its CIImage, PreviewSurfaceView renders using that space, and adjusted/original GPU publication paths pass request.space. Added regression coverage for P3 propagation and clear reset. Verification: swift test (431 passed, 24 skipped), swift build -c release, git diff --check; dg validate OK with only known runner-model/context warnings.


### Comment — pi @ 2026-09-01T02:32:54.897Z

## Verification Report — pi (counterpoint, after human review)

**Verdict: PASS** — no blockers, no fixes needed. Issue moved to `done`.

### Scope reviewed
Commit 2d8394a diff (AppViewModel.swift, PreviewSurface.swift, PreviewSurfaceTests.swift) and the
current working tree, checked against the specific ask: thread the WorkingSpace the presented
`CIImage` was rendered in through `PreviewSurface`/`PreviewSurfaceView` so the GPU surface renders
in the space actually requested, matching the CGImage path.

### Correctness
- Both GPU publication paths pass `request.space`: the adjusted path
  (`AppViewModel.swift:888`, `previewSurface.present(gpuImage, space: publication.request.space,…)` with
  `publication.request` from `PreviewCoordinator.render`) and the original path
  (`AppViewModel.swift:951`, `originalPreviewSurface.present(gpuImage, space: request.space)`). In
  each, the `CIImage` was produced by `engine.makeCIImage(request)`, which renders in `request.space`
  (`RenderEngine.swift:143-146`), so the stored `space` always matches the space the presented image
  was rendered in — exactly the contract the CGImage path uses (`makeCGImage`, `RenderEngine.swift:231`).
- `updateNSView` now calls `context.render(…, colorSpace: surface.space.cgColorSpace)` instead of
  `WorkingSpace.current.cgColorSpace`. `space` is set in `present` before `revision &+= 1`, so the
  `@Published revision` observation that triggers `updateNSView` always reads the current space — no
  race. `space` does not need to be `@Published`; it is read lazily at render time, like `image`.
- `clear()` → `present(nil)` resets `space` to `.current` (tested).

### Maintainability
Minimal, pattern-consistent change: a `space` field mirrors `image`; `present` gains a `space`
parameter defaulting to `.current` (matching the existing `WorkingSpace` default convention). Both
production call sites updated; no broad refactor, no public API/schema/migration change.

### Security
No new inputs, URIs, or secret handling. No concern.

### Performance
Negligible: one `WorkingSpace` → `CGColorSpace` resolution per draw (same cost as before) and a field
assignment in `present`. No per-frame allocation, no hot-path change.

### Swift 6 concurrency
No escape: `WorkingSpace` is `Sendable`; `space` is non-`@Published` `private(set)` main-actor state,
closed over the same way `image` is. No `@unchecked Sendable`/`nonisolated(unsafe)`/`@preconcurrency`.

### Checks run (declared in issue context)
- `swift test --filter PreviewSurfaceTests` — 2/2 pass (P3 propagation, clear reset).
- `swift test` (full suite) — 431 passed, 24 expected skips, 0 failures (matches implementation claim).
- `swift build -c release` — clean.
- `git diff --check` — clean (exit 0).
- `git show 2d8394a --stat` — 36 insertions / 5 deletions across the 3 expected files, no stray scope.

### Non-blocking findings
None. The `space`-set-without-`image` case (a space change alone would not redraw, since `updateNSView`
is revision-triggered) is inert today: both call sites always set a fresh space together with a fresh
image, and the P3 switch flags the need to revisit this seam if space ever becomes independently
mutable — the issue text already documents that future. Not a blocker and no ticket warranted.

### Verification commits
None — no source changes were required; this review made only `.dg/` bookkeeping edits.

## Agent log

- 2026-09-01T02:32:57.039Z: Verified PASS post-human-review: commit 2d8394a threads request.space through both GPU publication paths (adjusted + original) and PreviewSurfaceView renders with surface.space.cgColorSpace, consistent with the CGImage path. swift test 431 passed/24 skipped, release build clean, git diff --check clean. No fixes needed; moving to done.
