---
id: LUMO-040
title: Epic 7 — LUTs as an optional Look stage
type: feature
status: done
priority: high
labels:
  - mvp
  - epic
  - epic:lut
  - phase:7
created: 2026-08-30T18:30:30.653Z
updated: 2026-09-01T14:12:46.421Z
depends_on:
  - LUMO-041
  - LUMO-042
  - LUMO-043
order: zzzzh
board: product
---

## Objective

Preserve LUTzy's mature cube tooling while making a LUT an optional, durable operation within the broader editor.

## MVP outcome

- [x] None is a first-class state and LUT IDs survive scans/relaunch.
- [x] The Look browser remains fast and searchable.
- [x] Preview/export, copy/paste, undo, and persistence agree without regressing LUT derivation.

## Child tickets

- LUMO-041 — Harden optional LUT identity and resolution across persisted edits
- LUMO-042 — Reframe the LUT library as a Look inspector
- LUMO-043 — Verify LUT behavior through persistence, copy/paste, and full export

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

### Comment — codex @ 2026-09-01T14:11:10.624Z

Verified the complete optional Look integration across child tickets LUMO-041, LUMO-042, and LUMO-043. None and zero intensity follow the neutral path; stable LUT IDs survive scans and relaunch; the Look browser retains search, folders, and keyboard auditioning; and preview/export, per-photo persistence, copy/paste, undo, and derived-LUT behavior agree. Verification: swift test — 489 passed, 25 expected skips; swift build -c release — passed; git diff --check — passed; dg validate — OK with only the existing runner-model/context warnings.

### Comment — claude @ 2026-09-01T14:12:43.238Z

## Counterpoint verification (epic rollup, claude/sonnet)

Independent post-human-review check of Epic 7 as a whole, on top of the already-completed per-ticket counterpoint verifications for LUMO-041, LUMO-042, and LUMO-043 (all previously passed with no blockers; one localized dead-code fix in 5e5ece0).

Checks run on current HEAD (ecc38dc):
- `git status --porcelain -- Sources Tests` — clean, no uncommitted source drift.
- `swift test` — 489 passed, 25 expected skips, 0 failures.
- `swift build -c release` — clean (only pre-existing unrelated CIKernel/CIColorKernel deprecation warnings).
- `git diff --check` — clean.
- `dg validate` — OK, only the pre-existing runner-model warning.

Rollup review: read LUTWorkflowTests.swift end to end (navigation/relaunch persistence, multi-select copy/paste with per-photo undo) and skimmed the EditClipboard.swift/EditDocumentStore.swift diffs from LUMO-043. The epic's three MVP outcomes are each backed by a passing regression: None/zero-intensity neutral path and stable IDs (LUMO-041 tests), Look inspector search/folders/keyboard auditioning and scoped undoable reset (LUMO-042 tests), and preview/export/copy-paste/persistence agreement (LUMO-043's LUTWorkflowTests, which explicitly asserts paste affects exactly the selected photos and undo restores each independently). No cross-child integration gap found — no dangling references to the removed LUTSidebar/resetLUT() shim, no LUT-related code left uncovered by the three child diffs.

No blockers. No further backlog tickets warranted — this rollup found nothing beyond what the child verifications already covered.

Verdict: PASS. Closing the epic.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
