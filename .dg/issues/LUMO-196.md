---
id: LUMO-196
title: Persistent PhotoAnalysis cache + versioning
type: task
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:54.177Z
updated: 2026-09-04T14:34:43.456Z
depends_on:
  - LUMO-195
  - LUMO-194
order: zzzzzv
board: product
---

**Type:** Task
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/PhotoAnalysisCache.swift`
**Depends on:** LUMO-195, LUMO-194
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §5

## 1. Problem

`PhotoAnalysis` (the scalar facts — tone stats, region list, relationships, scene
characteristics) needs its own persistent cache, separate from `MaskStore` (LUMO-185), which
already handles mask *pixel* data. This split exists because `PhotoAnalysis` is small and
reconstructible from cached masks + a re-run of the (cheap) statistics/assembly step, while mask
pixels are the expensive part worth caching independently and are shared with the Masking UI's
different consumption pattern.

## 2. Requirement (acceptance criteria)

1. `struct AnalysisCacheKey: Sendable, Codable, Hashable` — `assetID`, `sourceFingerprint` (same
   definition as `MaskCacheKey`'s, LUMO-185 — reuse or share the fingerprint type so the two
   caches can't disagree about what invalidates them), `analysisVersion` (LUMO-182).
2. A persistent cache storing `PhotoAnalysis` keyed by `AnalysisCacheKey`, checked/written by
   `PhotoAnalysisCoordinator.analyze(...)` (LUMO-195).
3. Editing `EditDocument` fields (Light, Color, LUT, etc.) must **not** change the cache key or
   invalidate the entry — regression test this explicitly (same feedback-loop concern as
   `docs/PHASE3_SPEC.md` §5).
4. Bumping `AnalysisVersion` invalidates old entries cleanly.
5. Cache reads/writes are cancellable-safe.
6. Cache-hit latency target < 5 ms (`docs/PHASE3_SPEC.md` §6).
7. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Reuse `Sources/LumoKit/Models/EditDocumentStore.swift` /
  `Sources/LumoKit/ViewModels/EditPersistenceCoordinator.swift`'s persistence conventions, same as
  LUMO-185.
- Since `PhotoAnalysis` no longer embeds mask pixels (they're `RegionMaskReference`s into
  `MaskStore`), this cache should be simple/small — a JSON or plist blob per photo is likely
  sufficient; don't over-engineer storage here relative to LUMO-185's heavier mask store.

## 4. Where to look

- `Sources/LumoKit/Models/EditDocumentStore.swift`, `EditPersistenceCoordinator.swift`.
- LUMO-185's `MaskStore` — sibling cache to coordinate key/fingerprint definitions with.
- LUMO-175/176 — existing precedent on cancellation-safety for per-photo persistence flushes.

## 5. Testing

- `Tests/LumoKitTests/PhotoAnalysisCacheTests.swift` (new): write/read round-trip, cache-hit
  avoids recomputation, edit-document-changes-don't-bust-cache, version-bump-busts-cache,
  cancelled-write-doesn't-corrupt-store.
