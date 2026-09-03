---
id: LUMO-139
title: Define projection behaviour when import filters hide newly arrived photos or ordinals exceed the reserved count
type: task
status: done
priority: low
labels:
  - verification
created: 2026-09-02T17:56:59.805Z
updated: 2026-09-02T21:25:07.344Z
depends_on:
  - LUMO-129
order: a0
board: product
commits:
  - 2fbec7b
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run:
    - swift test --filter PhotosImportTests — 9 passed
    - swift test — 646 executed, 14 skipped, 0 failures
    - swift build -c release — passed
    - git diff --check — passed
    - dg validate — OK with pre-existing warnings
  findings: []
  fixes: []
  verification_commits:
    - 2fbec7b
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-02T21:25:07.342Z
  session: 01MTKLMIJ5HLFCX0LS
---

## Objective

Two edge cases in `ImageCollection.thumbnailEntries` (added for LUMO-129) are currently implicit. Decide the intended behaviour and cover it with tests:

1. **Filter interaction during an active import.** When a slot's asset arrives but does not match the active flag/rating filter, its entry is dropped (`return nil`) while sibling placeholders remain, so the visible count shrinks below the reserved count and an already-replaced slot disappears. This is probably acceptable, but it is undocumented and untested, and it differs from the no-import branch, where filtering is expressed through `filteredIndices`.
2. **Ordinal beyond the reservation.** An item appended with `ordinal >= reservedCount` (provider delivers more than `totalCount`, or a caller misuses the API) is inserted into `items` but has no slot, so it is invisible in the grid/filmstrip projection until `finishDataImport` clears the slots. There is no assertion or fallback guarding this invariant.

## Suggested direction

Pick one rule per case (e.g. "placeholders are always shown unfiltered; filtered-out arrivals collapse to nothing" and "ordinal ≥ reservedCount falls back to a tail placeholder or an assertion") and add `PhotosImportTests` coverage so the projection contract is explicit.

## Verification context

Found during counterpoint verification of LUMO-129 (commit 2288d66). Not a blocker: neither case is reachable through the current `PHPhotosPicker` flow (selection count equals enumerated ordinals, and filters are not user-changeable mid-import in the shipped UI).


### Comment — codex @ 2026-09-02T21:18:55.769Z

Implemented in commit 2fbec7b. Defined the streamed thumbnail projection contract: placeholders remain visible regardless of the active filter, filtered-out loaded arrivals collapse, and arrivals without a reserved ordinal are rendered as loaded tail entries instead of disappearing. Added PhotosImportTests coverage for filtering, overflow visibility/order, and completion cleanup. Verification: swift test --filter PhotosImportTests (9 passed); swift test (646 passed, 14 expected skips); swift build -c release passed; git diff --check passed; dg validate OK with pre-existing pickup-model and context-completeness warnings.


### Comment — claude @ 2026-09-02T21:25:02.678Z

Counterpoint verification (independent, post human-review) — PASS.

Reviewed commit 2fbec7b against the two edge cases from the objective:

1. Filter interaction during import: placeholders stay unfiltered (the `pendingImportSlots.compactMap` branch returns a placeholder entry unconditionally whenever the assetID/dataImportItemIndices lookup fails), while loaded arrivals are filtered via `filter.matches(...)` and collapse (`return nil`) when excluded. This matches the stated contract and mirrors the no-import `filteredIndices` branch's semantics for loaded items.
2. Overflow ordinals: `appendDataImport`'s `else` branch (no matching `pendingImportSlots` slot) now records the id in `dataImportOverflowItemIDs` instead of leaving the item unprojected; `thumbnailEntries` appends a filtered `overflowEntries` tail computed from `items`. Verified the set is correctly maintained across all lifecycle paths: cleared in `finishDataImport` and all three collection-reset sites, and removed on `applyMetadata`'s failure/removal path, so no dangling ids survive item removal.

Correctness: traced `appendDataImport`'s ordinal-ordered insertion (`dataImportOrdinals.firstIndex(where: { $0 > ordinal })`) — overflow items sort into `items` by ordinal the same as reserved ones, so the `overflowEntries` scan over `items.indices` yields tail entries in the right relative order.

Maintainability: doc comment on `thumbnailEntries` now states the filter/placeholder contract explicitly; inline comments on the overflow branch explain the defensive/unreachable-in-shipped-UI nature of the case.

Performance: `overflowEntries` adds one extra O(n) scan over `items` when `thumbnailEntries` is accessed mid-import; negligible next to the existing O(n) `reservedEntries` pass, and it only runs while `pendingImportSlots` is non-empty. Not a concern at current collection sizes.

Security: no new I/O, parsing, or trust-boundary changes; scope is purely in-memory projection logic.

Checks re-run this pass (HEAD 2fbec7b, tree clean before/after, no new commits):
- swift test --filter PhotosImportTests — 9 passed, 0 failed
- swift test (full suite) — 646 passed, 14 expected skips, 0 failed
- swift build -c release — succeeded
- git diff --check — clean
- dg validate — OK (pre-existing agents.pickup.runner model-name warning only, unrelated)

No blockers. No new backlog tickets warranted — both edge cases are now explicit, documented, and covered by dedicated tests. Clearing lease and moving to done.

## Agent log

- 2026-09-02T21:25:07.343Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- swift test --filter PhotosImportTests — 9 passed
- swift test — 646 executed, 14 skipped, 0 failures
- swift build -c release — passed
- git diff --check — passed
- dg validate — OK with pre-existing warnings
Findings:
- None
Fixes:
- None
Verification commits:
- 2fbec7b
Actor: claude
Resolved model: sonnet
Pickup session: 01MTKLMIJ5HLFCX0LS
Summary: Counterpoint verification passed: streamed thumbnail projection edge cases (filter-collapsed loaded arrivals, unreserved overflow ordinals) confirmed correctly implemented and tested in 2fbec7b.
