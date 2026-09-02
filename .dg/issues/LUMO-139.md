---
id: LUMO-139
title: Define projection behaviour when import filters hide newly arrived photos or ordinals exceed the reserved count
type: task
status: backlog
priority: low
labels:
  - verification
created: 2026-09-02T17:56:59.805Z
updated: 2026-09-02T17:56:59.805Z
depends_on:
  - LUMO-129
order: zzzq
board: product
---

## Objective

Two edge cases in `ImageCollection.thumbnailEntries` (added for LUMO-129) are currently implicit. Decide the intended behaviour and cover it with tests:

1. **Filter interaction during an active import.** When a slot's asset arrives but does not match the active flag/rating filter, its entry is dropped (`return nil`) while sibling placeholders remain, so the visible count shrinks below the reserved count and an already-replaced slot disappears. This is probably acceptable, but it is undocumented and untested, and it differs from the no-import branch, where filtering is expressed through `filteredIndices`.
2. **Ordinal beyond the reservation.** An item appended with `ordinal >= reservedCount` (provider delivers more than `totalCount`, or a caller misuses the API) is inserted into `items` but has no slot, so it is invisible in the grid/filmstrip projection until `finishDataImport` clears the slots. There is no assertion or fallback guarding this invariant.

## Suggested direction

Pick one rule per case (e.g. "placeholders are always shown unfiltered; filtered-out arrivals collapse to nothing" and "ordinal ≥ reservedCount falls back to a tail placeholder or an assertion") and add `PhotosImportTests` coverage so the projection contract is explicit.

## Verification context

Found during counterpoint verification of LUMO-129 (commit 2288d66). Not a blocker: neither case is reachable through the current `PHPhotosPicker` flow (selection count equals enumerated ordinals, and filters are not user-changeable mid-import in the shipped UI).
