---
id: LUMO-183
title: AnalysisImage pipeline + normalized point/rect coordinate system
type: feature
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:48.908Z
updated: 2026-09-04T14:34:39.321Z
depends_on:
  - LUMO-182
order: zzzq
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/AnalysisImage.swift` + point/rect coordinate types
**Depends on:** LUMO-182
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §3–4

## 1. Problem

Every analyzer and mask provider must operate against one canonical, downscaled representation of
the photo — never the source RAW buffer, never a representation each caller resizes for itself.
Lumo also needs one coordinate system: Vision APIs use their own normalized-coordinate
conventions, and mixing pixel/CI/Vision/UI/RAW-orientation coordinates by accident is exactly the
bug class this ticket prevents.

**Scope note (revised sequencing):** this ticket covers `NormalizedPoint`/`NormalizedRect` and
`AnalysisImage` only. `NormalizedMask` and everything mask-shaped now lives in LUMO-184 (`RegionMask`
core abstraction), which depends on this ticket for the point/rect types.

## 2. Requirement (acceptance criteria)

1. `NormalizedPoint`, `NormalizedRect` — `Sendable, Codable, Equatable` value types (not `CGRect`
   typealiases), origin upper-left, `0...1`.
2. `struct AnalysisImage: Sendable` — an opaque handle produced once per analysis run. Not
   `Codable` (only `PhotoAnalysis` results are cached, per LUMO-196). Internally it may wrap a
   `CIImage`/pixel buffer, but that must stay a private implementation detail — only the
   `Sendable` `AnalysisImage` wrapper crosses actor boundaries, mirroring how `RenderEngine` keeps
   `CIImage`/`CIContext` internal (`PHASE2_SPEC.md` §4.5).
3. `struct AnalysisImageFactory` (or free function) producing one `AnalysisImage` at a configurable
   longest-edge dimension from Lumo's existing decoded source (post-orientation-bake,
   pre-creative-edit):
   ```swift
   struct AnalysisConfiguration: Sendable {
       var maximumDimension: Int = 768
   }
   ```
   Leave `// TODO(LUMO-206): benchmark 512/768/1024` rather than hand-tuning now.
4. A documented, one-shot Vision-coordinate → `NormalizedRect`/`NormalizedPoint` conversion
   function — the **only** place permitted to know Vision's coordinate convention. LUMO-187 and
   every mask/region provider after it must call this, never reimplement it.
5. EXIF/RAW orientation applied before the canonical image is produced, reusing Lumo's existing
   orientation-bake path.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Reuse `Sources/LumoKit/Models/RenderPipeline.swift`'s scale-to-working-size logic where
  possible rather than duplicating resize math.
- The Vision-coordinate conversion function can be unit-tested now with synthetic Vision-shaped
  rects even though no real Vision adapter exists yet (that's LUMO-187).

## 4. Where to look

- `Sources/LumoKit/Models/RenderPipeline.swift`, `RenderEngine.swift` — resize/`CIImage`-stays-
  internal precedent.
- `Sources/LumoKit/Models/ImageDecoder.swift` — orientation baking.

## 5. Testing

- `Tests/LumoKitTests/AnalysisImageTests.swift` (new): produced image's longest edge matches
  `AnalysisConfiguration.maximumDimension`; orientation applied correctly (reuse the existing
  orientation-tagged JPEG fixture).
- `Tests/LumoKitTests/NormalizedCoordinateTests.swift` (new): round-trip synthetic Vision-
  convention rects through the conversion function.
