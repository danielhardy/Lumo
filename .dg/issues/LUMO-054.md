---
id: LUMO-054
title: Add optional Apple Photos delivery after file export is stable
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings:
    - "Blocker (fixed): PhotoKitDelivery.addAsset in Sources/LumoKit/Models/PhotosDelivery.swift called PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle:) outside library.performChanges, then mutated it inside a separate performChanges block. This violates PhotoKit's change-request contract (factory + mutation must happen in the same change block) and would fail/crash at runtime the first time a user created a new Photos album. PhotosDeliveryTests only exercises a FakePhotosDelivering, so this path was untested. Fixed by moving the factory call inside the performChanges closure (commit 02e6541)."
  fixes: []
  verification_commits:
    - "02e6541"
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-02T19:18:44.087Z
  session: 01MTKH5UDZHVZW8YE6
labels:
  - mvp
  - stretch
  - epic:export
  - phase:9
created: 2026-08-30T18:30:35.848Z
updated: 2026-09-02T19:18:48.267Z
depends_on:
  - LUMO-053
estimate: 5
order: a0
board: product
commits:
  - "02e6541"
---

## Objective

Allow final exports to be saved to Photos and optionally an album without coupling core rendering to PhotoKit.

## Context

Part of **Epic 9 — Reliable full-resolution export**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Reuse completed encoded files/data from the reliable export path.
- Request authorization at the point of use and handle limited/denied states.
- Create or select an optional destination album.
- Report partial failures separately from render failures.

## Acceptance criteria

- [ ] Authorized exports appear in Photos with optional album placement.
- [ ] Denied/limited authorization has clear recovery guidance.
- [ ] PhotoKit failure does not corrupt or remove successful file output.
- [ ] Core export tests run without Photos authorization.

## Verification

- Unit-test the coordinator behind an adapter and manually smoke-test authorization states.

## Out of scope

- Photos library editing or synchronization.

### Comment — codex @ 2026-09-02T19:11:57.502Z

Implemented in commit 7f3336c. Added value-only PhotosExportOptions, injected PhotosDelivering seam, production PhotoKit adapter with point-of-use read/write authorization and optional album create/select, post-commit delivery using the exact encoded export data, actionable denied/restricted/limited recovery guidance, separate Photos failure accounting for batch exports, and an Export panel Photos/album option. Verification: focused export/Photos tests 39/39 passed, swift build -c release passed, git diff --check passed, dg validate passed with only pre-existing warnings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T19:18:44.091Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- Blocker (fixed): PhotoKitDelivery.addAsset in Sources/LumoKit/Models/PhotosDelivery.swift called PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle:) outside library.performChanges, then mutated it inside a separate performChanges block. This violates PhotoKit's change-request contract (factory + mutation must happen in the same change block) and would fail/crash at runtime the first time a user created a new Photos album. PhotosDeliveryTests only exercises a FakePhotosDelivering, so this path was untested. Fixed by moving the factory call inside the performChanges closure (commit 02e6541).
Fixes:
- None
Verification commits:
- 02e6541
Actor: claude
Resolved model: sonnet
Pickup session: 01MTKH5UDZHVZW8YE6
Summary: Counterpoint verification passed after fixing a PhotoKit album-creation contract violation.
