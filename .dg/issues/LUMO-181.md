---
id: LUMO-181
title: Photo Intelligence & subject-aware Auto (epic)
type: task
status: ready
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
  - epic
created: 2026-09-04T13:45:19.425Z
updated: 2026-09-04T14:43:05.820Z
order: a0
board: product
---

**Type:** Epic
**Spec:** [`docs/PHASE3_SPEC.md`](../../docs/PHASE3_SPEC.md)
**Depends on:** none

## 1. What this is

Lumo's one-click Auto (`AutoAdjustmentSettings` / `AutoImageStatistics` /
`AutoAdjustmentAnalyzer` in `Sources/LumoKit/Models/AutoAdjustment.swift`, wired up in
`AppViewModel.runAutoAdjustment()`) works from a global luma/RGB histogram alone — it has no
concept of subject, face, or background. This epic tracks building a reusable, deterministic
**photo-understanding layer** as a first-class Lumo subsystem, not a one-off feature bolted to
the Auto button: it should power Auto, a user-facing Masking feature, and eventually smart crop
and other subject-aware tools.

Apple's Vision framework provides the primitives: attention-based saliency, foreground instance
masking, person segmentation, face detection. This epic's job is to wrap them behind a Lumo-owned
domain model so Auto and future features never touch `VN*Request` or `CIImage` directly — only
stable, `Sendable`, `Codable` values cross that boundary.

## 2. Binding architectural decision: masks are shared infrastructure, built first

**This is the one thing every child ticket must protect.** An earlier draft of this plan had
`PhotoAnalysis` grow its own private notion of a "region" with an embedded mask, and treated
person segmentation and a masking UI as late add-ons gated behind Auto shipping. That was wrong,
and the plan was revised before implementation started (LUMO-182–201 in the original decomposition
were deleted and rebuilt as LUMO-182–207 below): if masks are invented twice — once inside
`PhotoAnalysis`, once inside a later masking feature — the result is duplicated Vision calls,
duplicated caches, subtly different masks for the same photo, and coordinate-system bugs between
the two.

The dependency chain is now:

```text
IMAGE ANALYSIS FOUNDATION (coordinate system, canonical image)
        ↓
MASK FOUNDATION (RegionMask, MaskStore, MaskOperations, SemanticMaskProviding)
        ↓
VISION MASK PROVIDERS (subject, face, foreground/background, person)
        ↓
REGIONAL PHOTO ANALYSIS (masked statistics → PhotoAnalysis assembly → ensemble → relationships → scene)
       ↙ ↘
   Auto Light Engine     User-facing Masking UI
        ↓                        ↓
        (both consume the exact same RegionMask through the exact same
         SemanticMaskProviding / MaskedToneAnalyzer seam — they differ only
         in requested MaskQuality: Auto uses .analysis, the UI uses
         .preview/.render)
```

Concretely: Auto calls `maskService.mask(for: .subject, image:, quality: .analysis)` then
`toneAnalyzer.statistics(image:, through: subjectMask)`. The Masking UI calls the identical
`maskService.mask(for: .subject, image:, quality: .preview)`. Neither is allowed to have its own
mask representation, cache, or Vision call path. If any child ticket finds itself reading mask
pixels directly instead of going through `MaskedToneAnalyzer`/`MaskStore`, that's the bug this
whole restructure exists to prevent — stop and fix the shared abstraction instead.

## 3. Other non-negotiable principles (apply to every child ticket)

1. **`PhotoAnalysis` and `RegionMask` state facts, never recommendations.** No
   `recommendedExposure` field anywhere — that belongs to the Auto engine alone.
2. **One canonical analysis image, computed once**, ~768px longest edge (configurable,
   benchmarked in LUMO-206), shared by every provider/analyzer.
3. **One coordinate system** (`NormalizedRect`/`Point`/`Mask`, origin upper-left, 0...1),
   converted from Vision's own conventions exactly once, at the Vision adapter boundary
   (LUMO-187).
4. **Vision's ontology never leaks past the Vision adapter.** Everything becomes a `RegionMask`
   before anything else sees it.
5. **Mask quality is explicit and requested, not assumed.** `MaskQuality { analysis, preview,
   render }` lets Auto stay cheap while the Masking UI and local-adjustment rendering (LUMO-202)
   get precision only where it's actually needed.
6. **Analysis is demand-driven and gracefully degrading.** Only Tier 0 (global tone/color) is
   required; every mask kind is optional and each failure is recorded in `AnalysisQuality`, never
   fatal to Auto.
7. **Swift 6 clean, zero escape hatches** — same bar as the rest of `LumoKit`. Vision/Core Image
   adapters are actors; `PhotoAnalysis`/`RegionMask` and their contents are plain `Sendable`
   values; `AutoLightEngine` is pure value-in/value-out code, no actor isolation.
8. **Apple frameworks only** — no third-party ML, no Core ML model bundle in this phase.
9. **No image data leaves the device.** No network fallback is architected in anywhere.

## 4. Child tickets

See `docs/PHASE3_SPEC.md` §9 for the full table. Sequence:

`182` (core value types) → `183` (analysis image + coordinates) → `184` (RegionMask core
abstraction) → {`185` (MaskStore), `186` (MaskOperations)} → `187` (Vision mask-provider
boundary) → {`188` subject, `189` face, `190` foreground/background} → `191` (person, gated on
188/189/190's signals) → `192` (Tier 0 global tone) → `193` (masked statistics engine) → `194`
(PhotoAnalysis assembly) → `195` (coordinator) → `196` (PhotoAnalysis cache) → `197` (primary
subject ensemble) → `198` (region relationships) → `199` (scene characteristics) → `200` (Auto
Light engine) → `201` (Masking UI, depends on the mask providers directly, not on Auto) → `202`
(high-quality mask refinement) → `203`–`207` (debug overlay, fixture corpus, visual regression
harness, performance benchmarks, tuning).

Work roughly in dependency order via `dg next`/`dg ready`; the graph is wide in places (e.g.
188/189/190 can proceed in parallel once 187 lands) so independent agents can pick up siblings
concurrently.

## 5. Definition of done for the epic

- `LUMO-200` (Auto Light engine) exists, is pure/testable, and is wired into
  `AppViewModel.runAutoAdjustment()` as an additional, richer path — the existing Tier-0-only path
  must keep working when analysis is degraded or unavailable.
- `LUMO-201` (Masking UI) demonstrably reuses the same `RegionMask`/`MaskStore` infrastructure
  Auto uses — no parallel mask implementation exists anywhere in the codebase.
- `LUMO-204`/`LUMO-205` (fixture corpus + visual regression harness) are in place and green.
- `swift test` stays green throughout; no `@unchecked Sendable` / `nonisolated(unsafe)` /
  `@preconcurrency` introduced anywhere in the subsystem.
