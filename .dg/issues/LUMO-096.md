---
id: LUMO-096
title: Use a stable mosaic layout for mixed-orientation library photos
type: task
status: done
priority: high
labels:
  - mvp
  - ux
  - epic:library
  - phase:3
created: 2026-09-01T17:47:13.410Z
updated: 2026-09-01T21:15:20.713Z
depends_on:
  - LUMO-021
  - LUMO-103
order: zzzzzy
board: product
---

## Objective

Make the library view a stable photo mosaic that handles alternating landscape and portrait images
without broken rows, overlap, unexpected gaps, or layout jumps.

## Context

The current grid gives every cell the same square treatment. Mixed orientations can cause the
library to break when neighboring thumbnails alternate between landscape and portrait, undermining
the grid-first browsing workflow.

## Acceptance criteria

- [ ] A library containing alternating landscape, portrait, and square photos lays out as a
  coherent mosaic with no overlap, clipping, broken rows, or unexplained blank cells.
- [ ] Thumbnails preserve their source orientation/aspect ratio without stretching; selection,
  active state, badges, and filenames remain attached to the correct photo.
- [ ] Scrolling and incremental thumbnail loading remain responsive for large libraries, preserving
  the lazy/virtualized behavior from LUMO-021.
- [ ] Layout remains stable as thumbnails arrive and when the window is resized or filters change.
- [ ] Add focused layout tests covering mixed orientations and representative viewport widths.

## Implementation notes

Relevant code: `Sources/LumoKit/Views/LibraryGridView.swift`, `LibraryGridLayout`, thumbnail sizing,
and library layout tests. Choose a deterministic masonry/justified-row strategy that keeps cell
identity and accessibility semantics intact.

### Comment — codex @ 2026-09-01T18:27:22.965Z

Implemented and committed as e8b2266. Replaced the fixed-square LazyVGrid with a justified-row LazyVStack mosaic driven by upright metadata aspect ratios, bounded row geometry, stable 4:3 fallback geometry, and durable per-photo cell IDs. Selection, active state, badges, filenames, accessibility hints, and demand-driven thumbnail lifecycle remain attached to each photo. Added mixed-orientation geometry coverage at 320/768/1280 widths plus invalid-ratio safety tests. Verification: swift test (536 passed, 26 expected RAW-environment skips), swift build -c release passed, git diff --check passed, dg validate passed with only the pre-existing pickup-model and LUMO-044 context warnings.

### Comment — claude @ 2026-09-01T18:37:23.617Z

## Independent verification (counterpoint agent): BLOCKED, returned to review

Re-ran the declared checks from a clean invocation: `swift build` clean; `swift test --filter
LibraryGridTests` — 4/4 passed, matching the implementer's report.

**Confirmed working:** justified-row mosaic math (`LibraryGridLayout.mosaicRows`) is correct and
well-tested for a fixed set of aspect ratios at 320/768/1280 widths — no overlap, positive widths,
stable source-order/cell-identity mapping, sane NaN/zero/extreme-ratio fallback. Cell identity,
selection/active state, badges, filenames, accessibility hint/trait, and the demand-driven
thumbnail lifecycle all stay attached to the correct photo (`LibraryMosaicRow`/`LibraryGridCell` in
`LibraryGridView.swift`). `.aspectRatio(contentMode: .fit)` is the right call now that a cell's
frame ratio is clamped/normalized and can diverge from the source image's true ratio.

**Unresolved blocker — layout reflow while metadata streams in, not covered by the added tests:**
`libraryAspectRatio` (`ImageCollection.swift:37-46`) falls back to 4:3 until `asset.dimensions`
resolves, and dimensions arrive via `ImageCollection`'s deferred-metadata pipeline, which is queued
unconditionally for every discovered item (`enqueueMetadata` at `ImageCollection.swift:375`) and
applied serially (`ImageCollection.swift:497-556`) — unlike thumbnails, this is not gated by
on-screen demand. Each arrival mutates `@Published items`, and `LibraryGridView.body` recomputes
`mosaicRows` over the *entire* filtered collection on every such mutation. I reproduced this
directly with a temporary test: a portrait fixture's `libraryAspectRatio` reads as the 4:3 fallback
immediately after discovery, then changes once metadata resolves — meaning any row containing that
item, and every row after it, gets re-laid-out with different geometry mid-session. That is exactly
the "layout jump" this issue set out to eliminate, and it's most visible in the primary case this
issue cares about (a freshly scanned mixed-orientation library). The same unconditional
whole-library metadata processing plus full-collection `mosaicRows` recompute per single-item
update is also a real, unbounded per-update cost for large libraries, at odds with "preserving the
lazy/virtualized behavior from LUMO-021."

None of `LibraryGridTests`' new cases exercise a ratio changing after a row is already computed —
they only feed `mosaicRows` a fixed, pre-resolved list.

**Action taken (per the unresolved-blocker protocol):** filed **LUMO-103** (urgent, `verification`
label, parent LUMO-096) to stop the reflow and scope the recompute. LUMO-096 now depends on
LUMO-103. Moving this issue back to `review` — the mosaic math itself is sound, but the layout
stability guarantee the issue's objective and first acceptance criterion require is not met for the
scan-in-progress case, and that's the scenario most likely to be hit in practice.

No code changes made during this pass: the fix requires scoping either the metadata pipeline or the
recompute trigger, which is broader than the localized-fix authority for a counterpoint pass (the
temporary reproduction test was written for verification only and was not committed).

### Comment — claude @ 2026-09-01T21:15:18.486Z

### Verification report — counterpoint agent (claude)

**Verdict: PASS.** The blocker filed in the previous pass (LUMO-103: reflow while metadata streams in, unbounded per-update recompute cost) is resolved, and a follow-on perf ticket (LUMO-104: memoize by item identities, superseding LUMO-103's revision-counter approach with a simpler ordered-itemIDs+width comparison in `LibraryMosaicLayoutCache`) has also landed on top of it. Both dependencies (LUMO-021, LUMO-103) are `done`.

**Re-verified against the current tree (commit 3dff79d):**
- `LibraryMosaicLayoutCache.rows` (`Sources/LumoKit/Models/LibrarySelection.swift:267-293`) short-circuits to `cachedRows` unless the ordered `itemIDs` or `width` changed — metadata-only mutations (which don't change item identity/order) reuse the frozen row geometry, eliminating both the layout-jump and the O(n) recompute-per-update cost the LUMO-103 blocker described. Confirmed the old bespoke `libraryLayoutRevision` bump-site mechanism was fully removed (no stale references), replaced by this simpler identity-based invalidation — a legitimate simplification, not a regression.
- Traced `LibraryGridView.body` (`Sources/LumoKit/Views/LibraryGridView.swift:28-37`): itemIDs/width are computed once per body pass and handed to the cache; row-hosting stays a `LazyVStack` so LUMO-021's virtualization is untouched.
- Cell identity, selection/active state, badges, filenames, accessibility hint/trait, and demand-driven thumbnail lifecycle remain correctly attached per photo (`LibraryMosaicRow`/`LibraryGridCell`), matching the first verification pass's findings — no change to that logic in the two follow-up commits.
- `.aspectRatio(contentMode: .fit)` inside the frozen-geometry frame correctly letterboxes/pillarboxes a late-resolving real ratio rather than stretching or clipping.
- Regression coverage in `Tests/LumoKitTests/LibraryGridTests.swift` includes `testMosaicCacheFreezesPlacedRowsWhenDeferredAspectRatioArrives` (mirrors the original reflow repro; asserts unchanged rows + `recomputeCount == 1`) and `testMosaicCacheRecomputesWhenOrderedItemIdentitiesChange` (asserts structural changes do invalidate), directly satisfying this issue's "layout remains stable... as thumbnails arrive" acceptance criterion and LUMO-103's regression-test requirement.

**Checks re-run independently (clean invocation, all matched reported results):**
- `swift test --filter LibraryGridTests` → 6 passed, 0 failed
- `swift test` (full suite) → 560 passed, 26 expected skips, 0 failed
- `swift build -c release` → build complete
- `git diff --check 3dff79d^ 3dff79d` → clean
- `dg validate` → OK (pre-existing unknown-model warning only)
- `git status --porcelain` on Sources/Tests → clean, no stray edits from this pass

No blockers. No new non-blocking findings beyond what's already tracked. All five acceptance criteria are met by the combination of e8b2266 + 7795037 + 3dff79d.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
