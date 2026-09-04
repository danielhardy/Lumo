---
id: LUMO-187
title: Vision semantic mask provider boundary
type: feature
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:50.510Z
updated: 2026-09-04T14:34:40.577Z
depends_on:
  - LUMO-183
  - LUMO-184
order: zzzz
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift`
**Depends on:** LUMO-183, LUMO-184
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §2, §8

## 1. Problem

Nothing in this subsystem may import `Vision` except one adapter. This ticket builds that
boundary as a concrete `SemanticMaskProviding` (LUMO-184) conformer — `VisionSemanticMaskProvider`
— **without** implementing any specific request; that's LUMO-188/189/190/191 (one per semantic
kind). Getting the seam right first means those four tickets are additive, not structural, and
each is independently swappable later (e.g. a future `CoreMLSemanticMaskProvider`) without Auto or
the Masking UI caring.

## 2. Requirement (acceptance criteria)

1. `actor VisionSemanticMaskProvider: SemanticMaskProviding` owning all direct `Vision` framework
   usage. No other file in `LumoKit` may `import Vision` after this ticket lands.
2. Internally, route `mask(for:image:quality:)` to per-kind Vision requests — this ticket can ship
   with every kind unimplemented (`throw`/`unsupported`) and let LUMO-188/189/190/191 each fill in
   one case; or implement the dispatch structure and leave the request bodies as clearly marked
   stubs. Either is fine as long as the dispatch shape doesn't need restructuring per follow-up
   ticket.
3. `struct VisionConfiguration: Sendable, Codable, Equatable` recording the Vision request
   revision(s) in use per kind — this is what `MaskCacheKey`'s provider-version component
   (LUMO-185) is derived from.
4. Verify and document the **minimum macOS version** for each Vision API this subsystem will use
   (attention saliency, foreground instance masking, person segmentation, face detection). Lumo's
   deployment target is macOS 14 (CLAUDE.md); `#available`-guard anything newer and fall back
   cleanly (mirrors CLAUDE.md's `CIRAWFilter.isHighlightRecoveryEnabled` precedent).
5. Vision calls are `async`, cancellable, wrapped so failure becomes a Swift `throw`/`nil` rather
   than a raw `NSError`/`VNError` past the boundary.
6. `VNRequest`/`VNImageRequestHandler` and friends never cross this actor's isolation boundary
   (mirrors `CIImage`/`CIContext` staying inside `RenderEngine`, `PHASE2_SPEC.md` §4.5).
7. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- This ticket ships with **no working mask kind** — it's infrastructure. Acceptance bar: the actor
  exists, compiles, conforms to `SemanticMaskProviding`, and a smoke test proves a
  `VNImageRequestHandler` can be constructed from an `AnalysisImage` and cancelled mid-flight.
- Coordinate conversion was already built in LUMO-183 — call it, don't reimplement it.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §2, §8; CLAUDE.md's "SDK vs deployment target" section.
- `Sources/LumoKit/Models/RAWCapabilities.swift` — existing capability-probing pattern.
- LUMO-184's `SemanticMaskProviding` protocol — the seam this actor conforms to.

## 5. Testing

- `Tests/LumoKitTests/VisionSemanticMaskProviderTests.swift` (new): actor construction, request-
  handler smoke test, cancellation-mid-flight test, unsupported-kind returns a clean error (not a
  crash) for kinds not yet implemented by follow-up tickets.
