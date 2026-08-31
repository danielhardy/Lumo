---
id: LUMO-007
title: Isolate edit state per photo during navigation
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:19.185Z
updated: 2026-08-31T03:23:24.308Z
depends_on:
  - LUMO-006
estimate: 5
order: z
board: product
---

## Objective

Replace the current carry-forward document behavior with per-photo edit sessions while preserving optional look auditioning as an explicit action.

## Context

Part of **Epic 1 — Durable per-photo edit domain**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Associate a document with stable asset identity.
- Load/save the active document on filmstrip and grid navigation.
- Seed RAW develop from each file's own as-shot capabilities.
- Prevent late renders from the previous selection from publishing over the new photo.

## Acceptance criteria

- [ ] Edits on photo A do not silently appear on photo B.
- [ ] Returning to A restores its unsaved in-session edits.
- [ ] Each RAW starts from its own as-shot develop defaults.
- [ ] Rapid navigation cannot publish stale preview, histogram, or capability state.

## Verification

- Add fake-engine navigation race tests and mixed RAW/standard session tests.

## Out of scope

- Disk persistence.
- Copy/paste UI.

### Comment — codex @ 2026-08-31T03:21:37.350Z

Implemented in commit 455a08c. Added stable PhotoAssetID-backed in-session documents, save/restore on navigation, collection-item identities for imported photos, per-RAW capability/as-shot isolation, and generation+asset guards for decode, preview, comparison, histogram, capabilities, and metadata publication. Added deterministic fake-engine race coverage plus mixed RAW/standard and per-RAW seed tests. Verification: swift test passed (312 tests, 20 expected skips, 0 failures); swift build -c release passed; dg validate OK with pre-existing model/context warnings.

### Comment — claude @ 2026-08-31T03:23:22.290Z

## Independent verification — PASS

Reviewed commit 455a08c against acceptance criteria and re-ran all checks independently.

**Correctness**
- `PhotoAssetID` gives file-backed, imported, and one-off data sources distinct stable identity; `load()` saves the outgoing document into `editSessions[activeAssetID]` before swapping in the incoming one (or a fresh `EditDocument()`), so edits on A never leak onto B and A's unsaved edits restore on return.
- Every async publisher (`schedulePreview`, `scheduleOriginalPreview`, `updateHistogram`, `refreshMetadata`, `refreshCapabilities`) captures `loadGeneration`/`assetID` at request time and re-checks both via `isCurrent(generation:assetID:)` before writing published state — confirmed this closes the race where a late render/probe from the previous selection could publish over the new photo.
- RAW develop seeding (`developValue(for:)` in `AppViewModel+Develop.swift`, pre-existing/unchanged) reads live `rawCapabilities`, which is now itself asset/generation-guarded, so each RAW's as-shot defaults are correctly per-photo rather than carried forward.
- `importPhotosData` correctly pairs `items.first` with the just-reset `collection.items` array (verified `addFromData` resets `items = []` before appending), so the derived `PhotoAssetID.imported(id)` matches the actual first item.

**Maintainability** — change is well-scoped to the four touched files plus tests; doc comments accurately describe the new invariants (esp. the `document` property comment and `isCurrent`).

**Security** — no new I/O, network, or unsafe deserialization surface. `PhotoAssetID.data` uses SHA256 via CryptoKit for content fingerprinting, appropriate for a non-cryptographic identity key.

**Performance** — `editSessions` is an unbounded in-memory dictionary for the app session's lifetime (no eviction). Acceptable: explicitly scoped as "smallest state needed... disk persistence is LUMO-008," and per-photo `EditDocument` values are small value types, not decoded images.

**Checks run**
- `swift build` — clean.
- `swift test` — 312 tests, 20 expected skips (local-RAW-only tests, no DNG fixture on this machine), 0 failures. Includes the new `PhotoEditSessionTests` race/isolation suite.
- `swift build -c release` — clean.
- `git status --porcelain` — clean tree aside from pre-existing untracked `.dg` (unrelated to this change).

No blockers. No follow-up child tickets warranted — the one identified tradeoff (unbounded `editSessions`) is already a documented, deliberate deferral to LUMO-008, not a new gap.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
