---
id: LUMO-029
title: Epic 5 — White balance, mixer, and color grading
type: feature
status: done
priority: high
labels:
  - mvp
  - epic
  - epic:color
  - phase:5
created: 2026-08-30T18:30:26.827Z
updated: 2026-08-31T21:12:12.258Z
depends_on:
  - LUMO-030
  - LUMO-031
  - LUMO-032
  - LUMO-033
  - LUMO-034
order: zzx
board: product
commits:
  - 3ceeedc
---

## Objective

Deliver RAW-aware white balance plus global Color, eight-channel HSL mixer, and three-way color grading with high-quality GPU rendering.

## MVP outcome

- [x] As Shot, temperature/tint, vibrance/saturation, mixer, and grading persist and render at every quality.
- [x] Skin, foliage, saturated primaries, and gradients behave predictably.
- [x] No interactive stage uses Swift CPU pixel loops.

## Child tickets

- LUMO-030 — Implement As Shot and RAW-aware white balance behavior
- LUMO-031 — Harden Vibrance and Saturation as distinct global color controls
- LUMO-032 — Implement the eight-channel HSL Color Mixer
- LUMO-033 — Implement three-way Color Grading with blending and balance
- LUMO-034 — Ship responsive Color, Mixer, and Grading inspector sections

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

### Comment — codex @ 2026-08-31T21:11:05.231Z

Epic verification complete. Child tickets LUMO-030 through LUMO-034 are done and the integrated color workflow is present on main: RAW As Shot/temperature/tint with standard-image fallback, global Vibrance/Saturation, eight-channel HSL Mixer, and three-way Shadows/Midtones/Highlights grading with Blending/Balance. The shared RenderPipeline applies these stages at preview and full-resolution quality through Core Image GPU kernels; state is Codable/Equatable/Sendable, hashed, undoable, and persisted; photo navigation keeps RAW capability and white-balance seeds asset-specific. Focused tests cover RAW capability and direction, neutral/clamped mappings, HSL locality/overlap/wraparound, grading tonal regions/continuity, inspector resets/interaction, and preview/export parity. Verification: swift test — 418 passed, 21 expected RAW-environment skips; swift build -c release; git diff --check; dg validate. No interactive color stage uses Swift per-pixel loops. Auto white balance remains deferred because no reliable, testable Apple API was identified.

### Comment — claude @ 2026-08-31T21:12:10.190Z

Counterpoint verification (independent, post-review). Re-ran all checks on main @ a01379f: swift build (debug) clean; swift build -c release clean; swift test -> 418 passed, 21 expected RAW-environment skips, 0 failures; git diff --check clean. Confirmed all 5 child tickets (LUMO-030..034) are status=done. Read RenderPipeline.swift end-to-end: white balance goes through CIFilter.temperatureAndTint, vibrance/saturation through CIFilter.vibrance/colorControls, the 8-channel HSL mixer and 3-way grading each run as a single CIColorKernel (Metal-backed GPU pass, no CPU per-pixel loop) applied identically at preview and export scale via the shared buildImage() graph. ColorMixerAdjustments/ColorGradingAdjustments and their sub-structs are Codable+Equatable+Sendable as claimed. The only Swift-side pixel loops found in LumoKit (Histogram.swift, RecipeExtractor.swift) are non-interactive (histogram binning, offline LUT extraction), consistent with the epic's 'no interactive stage uses CPU pixel loops' outcome. No blockers found; verification passes. Auto white balance deferral (no reliable Apple API) remains an accepted non-goal, not a gap.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
