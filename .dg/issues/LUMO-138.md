---
id: LUMO-138
title: Avoid per-slot linear scans in ImageCollection.thumbnailEntries during streamed imports
type: task
status: done
priority: low
labels:
  - verification
created: 2026-09-02T17:56:57.146Z
updated: 2026-09-02T20:07:34.105Z
depends_on:
  - LUMO-129
order: zzzzy
board: product
commits:
  - 657d94c
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run:
    - swift test --filter PhotosImportTests — 7 passed
    - swift test — 643 executed, 14 skipped, 0 failures
    - swift build -c release — passed
    - git diff --check — passed
    - dg validate — OK with pre-existing warnings
  findings: []
  fixes: []
  verification_commits:
    - 657d94c
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-02T20:07:34.099Z
  session: 01MTKIVK1P0OJLP1WL
---

## Objective

`ImageCollection.thumbnailEntries` (added for LUMO-129) does an `items.firstIndex(where:)` scan per pending slot on every invocation, and it is invoked on each body evaluation of both `LibraryGridView` (twice: empty-state check + row build) and `FilmstripView`. For an N-photo import that is O(N²) `PhotoAssetID` comparisons per update, repeated several times per frame while assets stream in.

A secondary cost in the same code path: when `finishDataImport` clears `pendingImportSlots`, every entry's identity flips from the slot ID to the item ID in the same frame, so SwiftUI diffs the whole grid/filmstrip and `LibraryMosaicLayoutCache` rebuilds once. This is a one-time cost, but it lands exactly at the end of a large import when the UI is busiest.

## Suggested direction

- Maintain a `PhotoAssetID → items index` dictionary (or have `appendDataImport` record the slot's item index) so `thumbnailEntries` is O(slots).
- Consider letting loaded slot entries keep a stable identity across `finishDataImport` (e.g. reuse the item's source ID for the entry from the moment the asset arrives), so completion does not re-identity every cell.

## Verification context

Found during counterpoint verification of LUMO-129 (commit 2288d66). Not a blocker: measured behaviour is fine at realistic import sizes; this is a scalability/hygiene follow-up.

## Agent log

- 2026-09-02T20:07:34.105Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- swift test --filter PhotosImportTests — 7 passed
- swift test — 643 executed, 14 skipped, 0 failures
- swift build -c release — passed
- git diff --check — passed
- dg validate — OK with pre-existing warnings
Findings:
- None
Fixes:
- None
Verification commits:
- 657d94c
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTKIVK1P0OJLP1WL
Summary: Added an import-scoped PhotoAssetID-to-item-index cache for O(slots) thumbnail projection and kept loaded entry IDs stable through import completion. Added regression coverage.
