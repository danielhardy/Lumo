---
id: LUMO-104
title: Memoize library mosaic layout to avoid full recompute on every publish
type: task
status: done
priority: low
labels:
  - verification
  - epic:editor
  - phase:8
created: 2026-09-01T18:52:19.602Z
updated: 2026-09-01T21:21:51.926Z
order: zzzzzz
board: product
---

## Objective

`LibraryGridView.body` (Sources/LumoKit/Views/LibraryGridView.swift) calls
`LibraryGridLayout.mosaicRows` inline on every body evaluation. Because
`ImageCollection` is an `@ObservedObject`, any published change on it
(single-item selection, a thumbnail landing, etc.) re-triggers the full
O(n) aspect-ratio mapping + row-packing pass over the *entire* filtered
library, not just the visible viewport. For libraries with thousands of
RAW files this is real synchronous main-thread CPU work on every
selection/thumbnail update.

## Origin

Surfaced during independent verification review of LUMO-044 (Epic 8 —
image-centric editor experience). Non-blocking: `mosaicRows` itself is
correct (well-guarded against degenerate/NaN input per LUMO-096), the
concern is call-site recompute frequency, not the algorithm.

## Suggested fix

Memoize the mosaic result keyed on (item identities/count, container
width) instead of recomputing on every `ImageCollection` publish —
e.g. cache in the view model and recompute only when the input set or
width actually changes.

## Non-goals

No layout algorithm changes; this is purely about avoiding redundant
recomputation.


### Comment — codex @ 2026-09-01T21:13:10.329Z

Implemented in commit 3dff79d. Library mosaic geometry is now memoized by ordered filtered PhotoAssetID values and container width, so metadata, thumbnail, selection, and unrelated collection publishes reuse the existing rows; structural identity/order changes and resizes recompute. Added regression coverage for deferred aspect-ratio resolution and identity-order invalidation. Verification: swift test --filter LibraryGridTests (6 passed), swift test (560 passed, 26 expected skips), swift build -c release passed, git diff --check clean, dg validate OK with existing unknown-model and low-context warnings.


### Comment — claude @ 2026-09-01T21:21:50.120Z

Independent counterpoint verification: PASS.

Reviewed commit 3dff79d against the objective (avoid full mosaic recompute on every ImageCollection publish). The fix replaces the hand-maintained `libraryLayoutRevision` counter (incremented at ~10 call sites in ImageCollection) with memoization keyed on the ordered `[PhotoAssetID]` of `filteredIndices` plus container width, computed directly in LibraryGridView.body. This is a maintainability improvement over the revision-counter approach: it can't drift out of sync with a mutation site that forgot to bump it, since the cache key is derived structurally from current state every render.

Correctness checks:
- PhotoAssetID is Codable/Hashable/Sendable/Equatable, so `[PhotoAssetID]` array equality in the cache guard is well-defined.
- LibraryMosaicLayoutCache is @MainActor, held via `@State` in a View — no concurrency concern.
- Metadata-only updates (aspect ratio resolving from fallback) correctly reuse cached rows since identity/order/width are unchanged (testMosaicCacheFreezesPlacedRowsWhenDeferredAspectRatioArrives).
- Reordering without membership change correctly invalidates (testMosaicCacheRecomputesWhenOrderedItemIdentitiesChange).
- Remaining per-render cost is two O(n) passes (building itemIDs, array equality) instead of O(n) aspect-mapping + row-packing — consistent with the issue's non-goal of not touching the layout algorithm itself.

Verification commands run:
- swift build: succeeds, 0 diagnostics
- swift test --filter LibraryGridTests: 6/6 passed
- swift test (full suite): 561 tests, 26 expected skips, 0 failures
- swift build -c release: succeeds
- dg validate: OK (pre-existing unknown-model warning only, unrelated)
- git status --porcelain: clean w.r.t. tracked source (only unrelated .dg/ bookkeeping changes)

No blockers, no non-blocking follow-ups warranted — scope stayed within the stated non-goal (no algorithm change) and no new child tickets are needed.
