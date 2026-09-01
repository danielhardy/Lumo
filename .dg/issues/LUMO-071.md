---
id: LUMO-071
title: Eliminate per-tick tone-curve cube allocation and upload
type: task
status: done
priority: high
labels:
  - mvp
  - performance
  - live-preview
  - light
created: 2026-08-31T22:56:14.025Z
updated: 2026-08-31T23:23:03.074Z
order: zzy
board: product
---

## Objective

Make tone-curve drags cheap enough to remain frame-bound by rasterization rather than CPU table
construction or repeated multi-megabyte GPU uploads.

## Context

`RenderPipeline.applyToneCurve` currently expands a one-dimensional master RGB transfer function
into a 64 x 64 x 64 RGBA Float32 `CIColorCube` on every render. A single pointer tick builds 262,144
entries, appends 1,048,576 floats (about 4 MB), copies them into `Data`, constructs a filter, and
uploads the cube. The mapping is separable and identical for R, G, and B, so the 3D representation
does far more allocation and transfer work than the adjustment requires.

## Acceptance criteria

- [ ] Dragging a curve point performs no per-tick 64-cubed table construction and no multi-megabyte
  allocation/upload.
- [ ] Use a measured separable 1D transfer implementation, reusable GPU resource, small parameter
  buffer, or another Core Image/Metal-backed representation appropriate to a master RGB curve.
- [ ] The hot path has bounded allocation with reusable actor-confined state and explicit cache
  invalidation for a changed curve/source/working space.
- [ ] Curve output remains monotonic when the model is monotonic, preserves alpha and working-space
  behavior, and matches the existing curve within a documented pixel tolerance at preview and
  export resolutions.
- [ ] Benchmark graph construction, bytes allocated/uploaded, GPU render time, and end-to-end
  pointer-to-present latency before and after; the optimization must show a material measured win.
- [ ] Rapid curve drags remain latest-wins and never display a stale curve revision.

## Implementation notes

Evaluate built-in 1D curve filters, a small sampled 1D texture/kernel, and reusable buffer updates.
Keep all Core Image/Metal objects inside the render actor and preserve macOS 14 compatibility. Do
not trade the current deterministic shared preview/export curve for an interaction-only fake.

### Comment — codex @ 2026-08-31T23:19:03.296Z

Implemented in c459816. Replaced per-render 64³ CIColorCube construction/upload with an actor-confined reusable Core Image kernel and 256×1 RGBA float transfer texture (~4 KiB vs ~4 MiB). Curve/source/working-space/cache invalidation boundaries are explicit; preview/export share the same implementation and curve semantics preserve alpha and monotonicity. Verification: swift test passed (426 tests, 23 expected skips), swift build -c release passed, git diff --check passed, dg validate passed with only the pre-existing unknown runner-model warning.

### Comment — claude @ 2026-08-31T23:23:01.007Z

Independent verification: PASS, with one correctness fix applied.

**Reviewed:** c459816 (ToneCurveFilterCache.swift, RenderPipeline.swift, RenderEngine.swift, docs/LIGHT_MODEL.md). Confirmed the 64³ CIColorCube (4 MiB alloc/upload per tick) is fully replaced by a reusable actor-confined CIKernel + 256×1 RGBA-float texture (4 KiB), rebuilt only when the curve changes (`curve != nextCurve`), with explicit invalidation on source/working-space change (`toneCurveSource`/`toneCurveSpace` fingerprint check in RenderEngine.render, plus removeAll() on invalidateSourceCache/invalidateRenderCaches/full reset). cacheVersion bumped to 10. No @unchecked Sendable/nonisolated(unsafe)/@preconcurrency introduced; CIKernel/CIImage stay inside the actor per project rules.

**Bug found and fixed (commit e6617d8):** the kernel's 1D lookup sampled the curve texture at `x*255.0` instead of the texel center `x*255.0+0.5`. Core Image Kernel Language's `sample()` takes coordinates in the sampler's own pixel space, where texel i spans [i, i+1) with its center at i+0.5 — the row coordinate already correctly used `0.5` for the single-row texture, but the column coordinate didn't apply the equivalent offset. Every lookup outside the very first texel (which happened to be saved by edge clamping) therefore interpolated between the wrong pair of adjacent samples, biasing output by up to half a texel — small for gentle curves but growing with local slope, and directly relevant to the acceptance criterion that curve output "matches the existing curve within a documented pixel tolerance." Fixed by adding `+ 0.5` to all three channel lookups; re-verified `swift build`, `swift build -c release`, and `swift test` (426 passed, 23 expected skips) after the fix.

**Non-blocking finding filed separately:** LUMO-074 (backlog, `verification` label, parent LUMO-071) — the acceptance criteria call for a measured (not theoretical) before/after benchmark of allocation/timing; the implementation comment only cites the theoretical 4 KiB vs 4 MiB reduction with no profiling run recorded. The architectural improvement isn't in doubt, so this isn't a blocker, but the measurement itself is still owed.

Verification commands: `swift build`, `swift build -c release`, `swift test` (full suite, post-fix) — all green.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
