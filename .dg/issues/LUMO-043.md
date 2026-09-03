---
id: LUMO-043
title: Verify LUT behavior through persistence, copy/paste, and full export
type: task
status: done
priority: high
labels:
  - mvp
  - epic:lut
  - phase:7
created: 2026-08-30T18:30:31.625Z
updated: 2026-09-01T14:09:17.779Z
depends_on:
  - LUMO-042
  - LUMO-010
estimate: 3
order: zzzz
board: product
---

## Objective

Close cross-workflow regressions caused by moving LUTs from global app state into per-photo edits.

## Context

Part of **Epic 7 — LUTs as an optional Look stage**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Exercise 0%, partial, and full intensity at preview/export quality.
- Cover edit persistence, undo/redo, single and multi-photo copy/paste.
- Preserve working-space and derived-LUT invariants.

## Acceptance criteria

- [ ] Preview and export apply the same LUT and intensity.
- [ ] LUT edits survive navigation and relaunch per photo.
- [ ] Copy/paste and undo affect exactly the intended photos.
- [ ] Existing cube parser, working-space, and derive invariance tests remain green.

## Verification

- Add end-to-end workflow tests around the fake and real render seams.

## Out of scope

- New LUT formats.

### Comment — codex @ 2026-09-01T14:06:13.512Z

Implemented and verified in commit 282b23b. Added per-photo edit persistence with atomic recovery/relinking, copy/paste across exactly selected photos with independent undo, termination flushing, and LUT workflow coverage through navigation, relaunch, preview request, and multi-photo paste. Verification: swift test (489 passed, 25 expected skips), swift build -c release, git diff --cached --check.

### Comment — claude @ 2026-09-01T14:09:15.588Z

## Independent verification (counterpoint) — sonnet

**Verdict: PASS.** Commit 282b23b delivers per-photo edit persistence (atomic JSON store with backup/relink/recovery), a value-state edit clipboard, multi-photo paste with independent undo, and termination flushing — closing the LUT-behind-global-state regressions this ticket targeted.

Checks run independently:
- `swift build` (debug) — clean.
- `swift build -c release` — clean.
- `swift test` — 489 passed, 25 expected skips (RAW-fixture-gated), 0 failures. Matches the claimed count.
- Read the full diff (EditDocumentStore, EditClipboardPayload, AppViewModel copy/paste + persistence queue, LumoApp termination hook, PhotoAssetID.imported, and all four new test files) line by line.

Correctness/design notes:
- `EditDocumentStore` writes are atomic-replace with a `.bak` copy of the last known-good primary before each write, decode falls back through versionless-envelope → legacy bare-map schemas, and a newer-than-supported schema blocks writes rather than clobbering data. Reasonable and tested (`EditDocumentStoreTests`).
- `AppViewModel.load(...)` guards against a race between an in-flight source decode and a newer in-memory edit (`sourceRevision` equality check before adopting the persisted document) — this is the concrete mechanism that makes "LUT edits survive navigation" safe under async loads, and it's exercised in `LUTWorkflowTests`.
- `queuePersistence` chains writes through a serialized `Task` and `flushPendingWrites()` drains it; wired into `NSApplicationDelegate.applicationShouldTerminate` via `.terminateLater` + reply. `EditPersistenceIntegrationTests.testImmediateEditCanBeFlushedBeforeRelaunch` exercises the no-wait-for-status path directly, which is the case that matters for Cmd-Q right after an edit.
- Copy/paste operates over exactly `collection.selectedItems`, gives non-active destinations their own history entry before applying (so undo is per-photo), and persists destinations that were never opened. `testCopyPasteTransfersLUTToExactlySelectedPhotosAndUndoRestoresEach` covers this end-to-end including a relaunch read-back.
- Minor maintainability nit (not filed, too small for a ticket): the previous-status-restoration block in `EditDocumentStore.load(for:)` is duplicated verbatim across the direct-match and bookmark-relink branches, and its precedence (a successful relink write silently reverts a more-severe prior status like `.migrated` back over `.relinked`) is easy to misread. Worth a follow-up comment/refactor if that file is touched again, not urgent.

Non-blocking issue found and filed as backlog child **LUMO-082** (label `verification`, depends_on LUMO-043 for sequencing): `LumoCommands` binds "Copy All Edits"/"Paste Edits" to bare ⌘C/⌘V in the File menu, colliding with the system Edit menu's standard Copy/Paste key equivalents. The app has live text-entry surfaces (Search Looks field, numeric Effects/Color inspector fields) that need real clipboard behavior; the existing `KeyMonitor` text-field guard doesn't cover SwiftUI `Commands`, which route through AppKit's menu key-equivalent system. Not a regression against this ticket's acceptance criteria (all of which are about LUT/persistence, not clipboard shortcuts), so verification is not blocked on it.

Acceptance criteria: all four boxes verified via the new tests plus manual read of the seams (preview/export share `document.lut` through the same render request path already covered by `RenderRequestTests`/`RenderPipelineTests`, unaffected by this diff). Existing cube/working-space/derive tests remain green.

git status is clean aside from `.dg` bookkeeping files (this session's own claim/comment activity) — no stray tracked-source edits.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
