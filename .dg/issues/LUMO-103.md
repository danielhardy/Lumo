---
id: LUMO-103
title: Mosaic geometry reflows library rows as deferred metadata streams in
type: task
status: done
priority: urgent
labels:
  - verification
  - mvp
  - epic:library
  - phase:3
created: 2026-09-01T18:36:36.400Z
updated: 2026-09-01T19:41:07.902Z
order: zv
board: product
commits:
  - "7795037"
---

Parent: LUMO-096 (verification blocker — unresolved acceptance criteria)

## Objective

Stop the library mosaic from reflowing rows while a freshly-scanned folder's metadata is still
streaming in, and keep the row-geometry computation from doing full-collection work on every
single-item update for large libraries.

## Context

LUMO-096 replaced the fixed-square `LazyVGrid` with a justified-row mosaic
(`LibraryGridLayout.mosaicRows`, `Sources/LumoKit/Models/LibrarySelection.swift`) driven by each
item's `libraryAspectRatio` (`Sources/LumoKit/Models/ImageCollection.swift:37-46`). That property
falls back to a 4:3 placeholder until `asset.dimensions` is populated.

`ImageCollection`'s scan pipeline discovers files cheaply first, then queues metadata (including
dimensions) for **every** discovered item unconditionally and processes it serially
(`enqueueMetadata` called for each item right after its discovery batch is published,
`ImageCollection.swift:375`; single-consumer stream in `startMetadataLoading`,
`ImageCollection.swift:497-510`, not gated by visibility the way thumbnail demand is). Each
metadata arrival mutates the `@Published items` array (`ImageCollection.swift:555`), which
recomputes `mosaicRows` for the **entire** filtered collection inside `LibraryGridView.body`
(`Sources/LumoKit/Views/LibraryGridView.swift`, the `let rows = layout.mosaicRows(...)` call).

Two consequences, both against this issue's stated acceptance criteria:

1. **Reflow / layout jump.** Because row grouping is recomputed from scratch on every metadata
   arrival, and one item's ratio changing from the 4:3 fallback to its real ratio (e.g. a 1:3
   portrait or 2.35 panorama) shifts row boundaries for everything after it, visible items shuffle
   position while metadata is still streaming in during/after a fresh scan — the exact "layout
   jump" the issue was meant to eliminate. Reproduced directly: a temporary test loaded a single
   180x60 portrait fixture, read `items[0].libraryAspectRatio` before metadata resolved (4:3
   fallback, confirmed), then awaited `scanCompletion()`/`metadataCompletion()` and confirmed the
   ratio changed — i.e. any row containing that item (and everything after it) is recomputed with
   different geometry mid-session, with no debounce or freeze-once-laid-out behavior.
2. **Unbounded per-update cost.** `mosaicRows` is O(n) over the full filtered set and runs
   synchronously in the view body on every such mutation. Metadata is fetched for the whole library
   regardless of what's on screen (unlike thumbnails, which are demand-gated by
   `beginThumbnailDemand`/`requestThumbnail`/`releaseThumbnail`). For a library of thousands of
   items this means an O(n) mosaic recompute for each of up to n metadata arrivals during a scan —
   real load-time cost the "remains responsive for large libraries, preserving the
   lazy/virtualized behavior from LUMO-021" criterion was meant to rule out.

Not covered by the tests added in e8b2266 (`Tests/LumoKitTests/LibraryGridTests.swift`), which only
exercise `mosaicRows` as a pure function on a fixed, already-resolved aspect-ratio list — none of
them simulate a ratio changing after a row has already been computed/displayed.

## Acceptance criteria

- [ ] A freshly scanned folder's mosaic does not visibly reshuffle already-placed rows as deferred
  metadata resolves for items at or above the visible scroll position. Freezing geometry once an
  item's row has been computed, or otherwise avoiding a full-collection recompute per item, are
  both acceptable strategies — the fallback-then-jump behavior is not.
- [ ] Metadata work for aspect ratio (or the mosaic recompute it feeds) is proportional to what's
  needed for currently visible/near-visible rows, not O(n) per single-item update across the whole
  library, so scan-time responsiveness for large libraries matches the LUMO-021 lazy/virtualized
  bar.
- [ ] Add a regression test that simulates an item's aspect ratio changing after its row has
  already been laid out (mirroring the reproduction above) and asserts the previously-placed rows
  are not disturbed, or that the recompute is scoped rather than whole-collection.

## Out of scope

Broader rendering/virtualization rewrites beyond what's needed to fix the reflow and scope the
recompute. No new mosaic visual design.


### Comment — codex @ 2026-09-01T19:30:36.757Z

Implemented in 7795037. Added a stateful mosaic geometry cache keyed by collection layout revision and viewport width, so deferred metadata updates reuse already-placed rows instead of rebuilding full-collection geometry. Structural changes (scan membership/order, filters, culling, resize) invalidate the snapshot; lazy row hosting and thumbnail demand behavior remain unchanged. Added regression coverage for a laid-out 4:3 item resolving to a portrait ratio and asserting no row movement or recomputation. Verification: focused LibraryGridTests (5 passed), full swift test (557 passed, 26 expected skips), swift build -c release passed, git diff --check passed, dg validate passed with the existing unknown-model warning.


### Comment — claude @ 2026-09-01T19:41:05.238Z

### Verification report — counterpoint agent (claude)

**Verdict: PASS.** Independently re-reviewed 7795037 against both acceptance criteria and re-ran all checks reported by codex; results match.

**Correctness**
- `libraryLayoutRevision` is a structural-change counter, bumped on every mutation that changes filtered membership/order (`setFilter`, flag/rating/undo, scan reset, item removal, batch discovery merge — checked all 8 call sites) but explicitly *not* on `applyMetadata`'s success path (ImageCollection.swift:560-566), which only mutates `items[index].metadata`/`asset`. This is the correct split: metadata arrival changes `libraryAspectRatio` without bumping the revision, so `LibraryMosaicLayoutCache.rows` short-circuits to the cached snapshot instead of recomputing `mosaicRows` — verified by tracing every `items.append`/`items.remove`/`items =` site in ImageCollection.swift.
- Confirmed the failure-path removal (metadata read failure, line 572) does invalidate, correctly, since that changes collection membership.
- Checked the rendering consequence of freezing: `LibraryGridCell.thumbnail` uses `.aspectRatio(contentMode: .fit)` inside a frame sized from the frozen row geometry (LibraryGridView.swift:247,275), so a late-resolving real aspect ratio letterboxes/pillarboxes within the stale cell rather than stretching or clipping — no visual corruption, and the issue text explicitly names "freezing geometry once an item's row has been computed" as an acceptable (not just interim) strategy, so permanent freeze-until-next-structural-change is in spec, not a gap.
- `LibraryMosaicLayoutCache` is `@MainActor`, stored via `@State` in a SwiftUI view — safe, single-actor access only.

**Performance**
- Cache correctly avoids the O(n) `mosaicRows` recompute on metadata-only updates (`recomputeCount` stays 1 across a metadata mutation in the new test) — satisfies criterion 2 via recompute scoping, which the issue text allows as an alternative to gating metadata fetch itself.

**Checks re-run independently (all matched the reported results):**
- `swift test --filter LibraryGridTests` → 5 passed, 0 failed
- `swift test` (full suite) → 557 passed, 26 skipped, 0 failed
- `swift build -c release` → build complete
- `git diff --check 7795037^ 7795037` → clean
- `dg validate` → OK (pre-existing unknown-model warning only)

**Regression test** (`testMosaicCacheFreezesPlacedRowsWhenDeferredAspectRatioArrives`, LibraryGridTests.swift) directly mirrors the reproduction in the issue body: seeds three 4:3 fallback ratios, computes rows, then resolves item 0 to a 1:3 portrait ratio at the same revision, and asserts the row layout is unchanged and `recomputeCount` stays at 1. This satisfies acceptance criterion 3.

No blockers found. No new child tickets needed — no non-blocking issues surfaced beyond what's already in spec as acceptable.

## Agent log

- 2026-09-01T19:41:07.900Z: Independent verification passed: mosaic geometry freeze confirmed correct (revision counter excludes metadata-only mutations), all reported checks re-run and matched (557 tests, release build, diff-check, dg validate).
