---
id: LUMO-185
title: "MaskStore: mask caching and versioning"
type: task
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:49.718Z
updated: 2026-09-04T14:34:39.939Z
depends_on:
  - LUMO-184
order: zzzx
board: product
---

**Type:** Task
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/MaskStore.swift`
**Depends on:** LUMO-184
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` (revised mask-foundation sequencing)

## 1. Problem

`RegionMask` (LUMO-184) references its pixel data via `RegionMaskReference` rather than embedding
it, so there must be a store: something that persists mask pixel data, keyed consistently with
`PhotoAnalysis`'s own cache (LUMO-196), and versioned the same way. This is the mask-specific twin
of what an earlier draft of this plan folded into one generic "analysis cache" ticket — it's split
out now because masks are large, reusable across quality levels, and consumed by two independent
features (Auto and the Masking UI), so their storage/versioning story deserves to be solved once,
here, not duplicated.

## 2. Requirement (acceptance criteria)

1. A persistent, concurrency-safe store (actor, or otherwise `Sendable`-safe) — `MaskStore` —
   with roughly:
   ```swift
   actor MaskStore {
       func mask(for key: MaskCacheKey, quality: MaskQuality) async -> RegionMaskReference?
       func store(_ pixels: /* mask pixel data */, for key: MaskCacheKey, quality: MaskQuality) async -> RegionMaskReference
   }
   ```
2. Cache key includes asset identity, source fingerprint (same notion LUMO-196 will use for
   `PhotoAnalysis` — coordinate the exact `SourceFingerprint` definition with that ticket so the
   two caches agree on what invalidates them), `SemanticMaskKind`, `MaskQuality`, and a mask-
   provider/Vision-configuration version (from LUMO-187).
3. **Different quality levels for the same semantic kind are cached independently** and a lookup
   for `.render` does not silently return a stale/lower-quality `.analysis` mask — but a store
   *may* expose a helper that finds the best available quality at or above a requested minimum, as
   an explicit, separate call (this is what LUMO-202's quality-upgrade path uses).
4. Editing the document (Light, Color, LUT, etc.) does **not** invalidate cached masks — masks
   describe the source scene, same non-invalidation rule as `docs/PHASE3_SPEC.md` §5 establishes
   for `PhotoAnalysis`. Regression-test this explicitly.
5. Survives app relaunch (persistent, not an in-memory-only cache).
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Reuse Lumo's existing per-photo persistence conventions
  (`Sources/LumoKit/Models/EditDocumentStore.swift`,
  `Sources/LumoKit/ViewModels/EditPersistenceCoordinator.swift`) for the on-disk location/format
  style rather than inventing a parallel mechanism.
- Mask pixel data can be reasonably large at `.render` quality — consider a simple on-disk image
  format (e.g. single-channel PNG/HEIF) rather than a custom binary blob, so masks are inspectable
  during development.
- Cancelled writes must not corrupt the store — mirror the cancellation-safety discipline already
  established for per-photo persistence flushes (see LUMO-175/176's precedent, cited from the
  earlier revision of this plan, for raced/cancelled flush edge cases in this exact area).

## 4. Where to look

- `Sources/LumoKit/Models/EditDocumentStore.swift`, `EditPersistenceCoordinator.swift` — existing
  persistence pattern.
- `Sources/LumoKit/Models/BoundedCache.swift` — existing in-memory cache primitive, usable as a
  front for the persistent store.
- LUMO-184 — `RegionMaskReference`, `MaskCacheKey`, `MaskQuality` this store operates on.

## 5. Testing

- `Tests/LumoKitTests/MaskStoreTests.swift` (new): write/read round-trip per quality level;
  independent-quality-caching (§2.3); edit-document-changes-don't-bust-cache (§2.4); cancelled-
  write-doesn't-corrupt-store; persists across a simulated relaunch (reopen the store from disk).
