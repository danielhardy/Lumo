---
id: LUMO-005
title: Epic 1 — Durable per-photo edit domain
type: feature
status: done
priority: urgent
labels:
  - mvp
  - epic
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:18.651Z
updated: 2026-08-31T13:27:33.090Z
depends_on:
  - LUMO-006
  - LUMO-007
  - LUMO-008
  - LUMO-009
  - LUMO-010
order: zy
board: product
---

## Objective

Make every source photo own a small, versioned, persistent nondestructive edit record that supports navigation, undo, and edit transfer.

## MVP outcome

- [ ] Edits are isolated per stable photo identity and survive relaunch.
- [ ] Undo/redo groups continuous gestures correctly.
- [ ] Copy/paste can apply edits to one or many selected photos without touching originals.

## Child tickets

- LUMO-006 — Version the durable edit schema and rendering pipeline identity
- LUMO-007 — Isolate edit state per photo during navigation
- LUMO-008 — Persist per-photo edit records with atomic recovery
- LUMO-009 — Implement per-photo undo and redo with gesture grouping
- LUMO-010 — Copy and paste edits to one or many photos

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

### Comment — codex @ 2026-08-31T13:17:03.488Z

Implemented Epic 1 durable per-photo edit domain by integrating the completed child work: versioned EditDocument/render-pipeline identity; stable per-photo sessions with navigation race guards and RAW as-shot isolation; actor-isolated JSON persistence with atomic recovery, relinking, and clean-quit flush; bounded gesture-grouped per-photo undo/redo; and versioned copy/paste with RAW-safe develop policy, multi-selection, and undoable destinations. Fixed the integration seam so persisted documents restore into PhotoEditSession while preserving history isolation. Verification: swift test passed (340 tests, 20 expected skips, 0 failures); swift build passed; swift build -c release passed; git diff --check passed; dg validate passed with only pre-existing model/context warnings. Commits: 2fb3757, d8552f5, 0e92ade, 806bf32.

### Comment — claude @ 2026-08-31T13:27:30.718Z

Independent verification (counterpoint pass) — PASS, with one fix landed.

Scope: reviewed the integration seam that ties together the four child tickets (LUMO-006/007/008/009/010) for correctness, maintainability, and durability against the epic's MVP outcomes.

Checks run:
- swift build: clean
- swift test: 340/340 passing (20 expected skips) before my change; 341/341 after adding a regression test
- swift build -c release: clean
- git diff --check: clean
- dg validate: OK (pre-existing unrelated warnings only)
- Manual trace of the load/save race in AppViewModel.load() (806bf32): the "in-memory session wins over the disk snapshot" comment holds up — saveActiveDocument() syncs editSessions[activeAssetID] synchronously on every edit, including ones made while a decode is still in flight, so the async load completion correctly prefers it.

Finding (fixed): multi-select paste to non-active photos (LUMO-010, AppViewModel.pasteEdits' non-active branch) wrote the new EditDocument into the in-memory `editSessions` dictionary only. It never queued a disk write via EditDocumentStore, unlike every other mutation path (updateDocument, setLUTIntensity, undo/redo), which all funnel through saveActiveDocument(). Consequence: pasting to a selection of photos, then quitting before individually visiting each destination (making it active and then navigating away, which is what actually triggers a save), silently dropped those edits — reproducible against the "survive relaunch" + "apply to one or many" MVP outcomes together. flushPendingWrites() only awaits the existing persistenceTask chain, so there was nothing to flush for those destinations.

Fix (localized, no API/schema change): extracted the disk-queuing tail of saveActiveDocument() into a shared `queuePersistence(_:for:reportsStatus:)`, called from both the active-document path (reportsStatus: true, unchanged behavior/status reporting) and the non-active paste-destination path (reportsStatus: false, so a background paste write can't stomp on the open photo's editStoreStatus/statusMessage). Added a regression test, `testPasteToAnUnvisitedDestinationSurvivesATerminationStyleFlush` in EditPersistenceIntegrationTests, that pastes to an unvisited destination, does a termination-style flush, relaunches against the same store, and asserts the edit survived.

Commit: 2c944bd — "Persist multi-select paste edits for photos that are never visited"

No other blockers found. Recommending done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
