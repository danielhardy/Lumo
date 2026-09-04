---
id: LUMO-195
title: "Analysis coordinator: cancellation + request dedup"
type: task
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:53.761Z
updated: 2026-09-04T14:34:43.148Z
depends_on:
  - LUMO-187
  - LUMO-192
order: zzzzzq
board: product
---

**Type:** Task
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift`
**Depends on:** LUMO-187, LUMO-192
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §5, original proposal §11–12

## 1. Problem

Multiple callers (editor entry, thumbnail prefetcher, the Masking UI) can request masks/analysis
for the same photo at roughly the same time — without coordination that means duplicate Vision
passes. Work must also be cancellable, mirroring the existing `autoAdjustmentTask?.cancel()`
discipline in `AppViewModel.runAutoAdjustment()`. Note this coordinator now serves **two**
consumers with different needs: Auto wants a full `PhotoAnalysis` at `.analysis` mask quality; the
Masking UI (LUMO-201) wants individual masks, often at `.preview`/`.render` quality, without
necessarily wanting a full `PhotoAnalysis` recomputed.

## 2. Requirement (acceptance criteria)

1. `actor PhotoAnalysisCoordinator` exposing (at least) two entry points:
   ```swift
   func analyze(assetID: PhotoAssetID, source: ..., level: PhotoAnalysisLevel) async throws -> PhotoAnalysis
   func mask(assetID: PhotoAssetID, source: ..., kind: SemanticMaskKind, quality: MaskQuality) async throws -> RegionMask
   ```
   The second is what the Masking UI calls directly — it should **not** need to go through a full
   `analyze(...)` call to get one mask; it should reuse whatever's already cached (`MaskStore`,
   LUMO-185) and only compute what's missing.
2. Concurrent calls for the same underlying work (same `assetID` + `sourceFingerprint` +
   requested kind/quality, or same `level`) share one in-flight `Task` — test with N concurrent
   calls, assert the underlying provider ran exactly once.
3. `enum PhotoAnalysisLevel { case fast, standard, detailed }` (per `docs/PHASE3_SPEC.md` §4) maps
   to which mask kinds + `MaskQuality` get requested for a full `analyze(...)` call; this ticket
   only needs Tier 0 wired for real (LUMO-192) — later tickets (LUMO-197+) don't need to touch the
   coordinator's structure again, just register as additional stages.
4. Every awaited stage checks `Task.checkCancellation()` between stages.
5. No `@MainActor` requirement anywhere in this actor.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Look at `DeriveCoordinator` and `AppViewModel.autoAdjustmentTask` for the existing
  cancel-on-supersede shape to match, rather than inventing a new one.
- Structure the stage list so it's a small internal registry, not a hardcoded call chain — every
  mask-provider ticket that already landed by the time this is implemented (LUMO-188/189/190/191,
  if sequenced first) can register as a stage; if this ticket is implemented before all of them
  exist, keep it registry-shaped so late arrivals don't require restructuring.

## 4. Where to look

- `Sources/LumoKit/ViewModels/DeriveCoordinator.swift`.
- `Sources/LumoKit/ViewModels/AppViewModel.swift:861-913` (`runAutoAdjustment`).
- `Sources/LumoKit/Models/ImageWorkScheduler.swift` — existing scheduler patterns.

## 5. Testing

- `Tests/LumoKitTests/PhotoAnalysisCoordinatorTests.swift` (new): concurrent-dedup test for both
  entry points, cancellation test, direct-mask-request-doesn't-require-full-analyze test (assert a
  `mask(...)` call doesn't trigger unrelated stages).
