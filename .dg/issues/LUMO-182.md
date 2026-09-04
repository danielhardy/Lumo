---
id: LUMO-182
title: Core analysis value types (ToneStatistics, ColorStatistics, quality/timings)
type: feature
status: ready
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:48.514Z
updated: 2026-09-04T14:43:07.677Z
order: n
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/` (suggested new group)
**Depends on:** none (foundation ticket)
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §3

## 1. Problem

Before any statistics or mask code exists, Lumo needs the small, shared value types that both the
tone analyzer (LUMO-192) and the mask/region system (LUMO-184+) will build on. This ticket is
scoped **narrowly** to those primitives — it does not include `AnalyzedRegion` or any mask-related
type (those now live in LUMO-184, the `RegionMask` foundation ticket, per the revised
mask-first sequencing) and it does not include the full `PhotoAnalysis` struct (that's assembled
in LUMO-194, once masks and regional statistics exist to fill it).

## 2. Requirement (acceptance criteria)

1. `struct ToneStatistics: Sendable, Codable, Equatable` — `minimum`, `maximum`, `mean`, `p01`,
   `p05`, `p10`, `p25`, `p50`, `p75`, `p90`, `p95`, `p99`, `shadowClippingFraction`,
   `highlightClippingFraction`. Support both `linear` and `perceptual` luminance variants (either
   as two instances behind a small wrapper, or a reused `LuminanceDistribution` type — pick one,
   document why).
2. `struct ColorStatistics: Sendable, Codable, Equatable` — `meanRGB`/`medianRGB`
   (`SIMD3<Float>`), `saturationMedian`, `saturationP95`, `channelClipping`,
   `estimatedNeutrality`, `colorfulness`.
3. `struct AnalysisQuality: Sendable, Codable, Equatable` — one `Bool` per optional analysis tier
   (`globalToneAvailable`, `attentionAvailable`, `foregroundAvailable`, `faceAnalysisAvailable`,
   `peopleAnalysisAvailable`) plus `overallConfidence: Float`.
4. `struct AnalysisTimings: Sendable, Codable, Equatable` — one `Duration` per stage
   (`imagePreparation`, `globalTone`, `faceDetection`, `saliency`, `foregroundMasking`,
   `personSegmentation`, `regionalAnalysis`, `total`).
5. `struct AnalysisVersion: Sendable, Codable, Equatable, Hashable` (or `UInt16`) with bump-on-
   change discipline, mirroring `AutoAdjustmentSettings.currentVersion`'s clamp pattern in
   `Sources/LumoKit/Models/AutoAdjustment.swift:11-31`.
6. None of these types names an edit parameter (no `recommendedExposure` etc.) — facts only.
7. Swift 6 clean, zero escape hatches. No `Vision`/`CoreImage` import anywhere in this module.

## 3. Implementation notes

- Match the house style of `Sources/LumoKit/Models/EditDocument.swift` /
  `AdjustmentNode.swift` (small `Sendable, Codable, Equatable` value types, `static let
  neutral`/`.default` conveniences).
- Do **not** add `AnalyzedRegion`, `RegionKind`, or anything mask-related here — LUMO-184 owns
  that, and it's the type most at risk of drifting into two competing shapes if two tickets both
  try to define it. If you're tempted to add a mask reference field to any type in this ticket,
  stop and check whether LUMO-184 should own it instead.

## 4. Where to look

- `Sources/LumoKit/Models/AutoAdjustment.swift` — existing Tier-0 statistics + version-clamp
  precedent.
- `Sources/LumoKit/Models/EditDocument.swift`, `AdjustmentNode.swift` — house style.
- `docs/PHASE3_SPEC.md` §3.

## 5. Testing

- `Tests/LumoKitTests/AnalysisValueTypesTests.swift` (new): `Codable` round-trip for every type
  above, both fully-populated and default/neutral states. Version-clamp behavior if used.
- `swift test` stays green; no `@unchecked Sendable` anywhere.
