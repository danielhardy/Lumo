---
id: LUMO-129
title: Show pending thumbnail slots during multi-photo import
type: feature
status: done
priority: medium
verification_agent: pi
verification_model: openrouter/z-ai/glm-5.3-flash
labels:
  - import
  - ux
created: 2026-09-02T12:45:18.820Z
updated: 2026-09-02T17:58:40.221Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-02T17:58:40.219Z
---

## Objective

Show reserved pending thumbnail slots while multiple photos are importing.

## Context

Multi-photo import currently exposes only a small progress indicator in the bottom-right corner.
Because the library grid/filmstrip does not show where incoming photos will land, users receive
little feedback about the number of items still loading or whether the import is progressing. The
placeholders should complement the existing progress bar and make the destination UI visibly react
without implying that a photo is ready before its thumbnail has arrived.

## Acceptance criteria

- [ ] Starting a multi-photo import reserves one visible blank/loading thumbnail slot per incoming
      photo in the destination thumbnail view, in import order.
- [ ] Each placeholder is replaced by the corresponding thumbnail as that photo becomes available;
      placeholders do not reorder already-imported photos or shift unexpectedly.
- [ ] Placeholder state is visually distinct from a loaded image and remains usable with partial
      failures, cancellation, and empty imports; the existing progress indicator still works.
- [ ] Selection, navigation, and editing cannot target a placeholder as if it were a fully loaded
      photo, and completed imports leave no stale blank slots.
- [ ] Add UI/model coverage for batch counts, progressive replacement, cancellation/failure, and
      final cleanup.

## Implementation notes

Use the existing import/thumbnail scheduling state as the source of truth and keep placeholders
lightweight: reserve identity/order metadata without decoding or allocating fake image content.
Coordinate with `ImageCollection`, `Thumbnails`, and the library/filmstrip presentation so updates
are incremental and do not trigger an avoidable full-library reload.

### Comment — codex @ 2026-09-02T17:48:53.700Z

Implemented in commit 2288d66. Streamed Photos imports now reserve one lightweight, ordered thumbnail slot per selected photo; successful assets replace their ordinal slot in place, failures show a distinct unavailable state, and placeholders are excluded from selection/navigation. Grid and filmstrip render the incremental projection, while completion, cancellation, metadata failure, and empty imports clean up reservations. Verification: PhotosImportTests 6/6 passed; full swift test 628 passed, 13 skipped, 1 known unrelated CropWorkflowTests flake; swift build -c release, git diff --check, and dg validate passed (existing pickup-model warning).

### Comment — pi @ 2026-09-02T17:58:37.942Z

## Counterpoint verification report (independent review)

**Verdict: PASS — no blockers.** Two non-blocking findings filed as backlog children (LUMO-138, LUMO-139).

Reviewed commit 2288d66 against the objective and acceptance criteria.

**Correctness**

- Ordered reservation: `beginDataImport(reservedCount:)` creates one lightweight `PendingImportSlot` per selected photo (no `PhotoAsset`, no source bytes, no fake image allocation); `appendDataImport` inserts items by ordinal (`dataImportOrdinals.firstIndex(where: >)`), so out-of-order arrival preserves picker order, and slot ↔ item linkage by source `PhotoAssetID` is consistent across the append, metadata-failure, and finish paths.
- Progressive replacement: slots are replaced in place (the entry keeps the slot ID while loaded; `.id(item.id)` is applied only as the scroll-target identity), and the mosaic cache is keyed on entry IDs/width, matching the documented snapshot policy — the placeholder 4:3 → real-ratio transition behaves exactly like the accepted metadata-update non-reflow.
- Distinct placeholder state and partial failures: pending renders a ProgressView, failed renders `photo.badge.exclamationmark` + "Unavailable"; `recordDataImportFailure(ordinal:)` marks exactly the failed ordinal; the metadata-failure path converts the slot in place and removes the item while keeping `items`/`dataImportOrdinals` in sync; `isActive` accounts for slots in both the failure and finish paths, so a fully-failed import deactivates the destination.
- Selection/navigation safety: entries carry `itemIndex` only for loaded items; placeholders have no tap or keyboard handlers and never enter `filteredIndices`; finish, cancellation, metadata failure, and empty imports all clear reservations (test-asserted), leaving no stale blanks.
- Incremental updates: no full-library reload during import; the only identity churn is the documented one-time entry-ID flip at `finishDataImport` (backlogged as part of LUMO-138).
- Swift 6: no new concurrency opt-outs; all new state is MainActor-confined value data; `PackageSettingsTests` still enforces the zero-opt-out property.
- Security: no new file I/O, network, or privilege surface; slots carry only name/state metadata.

**Checks run**

- `swift build` — OK
- `swift test` — 629 passed, 13 skipped, 0 failures (includes PhotosImportTests 6/6 with the new reservation, out-of-order replacement, failure/cancellation, and empty-import coverage)
- `swift build -c release` — OK
- `git diff --check` — clean
- `dg validate` — OK (pre-existing pickup-model warning only)

**Findings (non-blocking, backlogged)**

- LUMO-138: `thumbnailEntries` performs an O(slots × items) scan per view update and entry identities flip at `finishDataImport` — scalability/hygiene follow-up.
- LUMO-139: behaviour is implicit for filtered-out arrivals during an active import and for ordinals ≥ the reserved count; needs an explicit contract plus tests.

**Verification commits**

None to tracked source — no code fixes were required; this report and the two backlog children are the only changes.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T17:58:40.220Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: unknown
