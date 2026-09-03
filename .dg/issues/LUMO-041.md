---
id: LUMO-041
title: Harden optional LUT identity and resolution across persisted edits
type: task
status: done
priority: high
labels:
  - mvp
  - epic:lut
  - phase:7
created: 2026-08-30T18:30:30.848Z
updated: 2026-09-01T13:38:39.078Z
depends_on:
  - LUMO-008
  - LUMO-014
estimate: 3
order: zzzx
board: product
---

## Objective

Audit the existing LUTSettings/LUTID/registry implementation against per-photo persistence, pipeline versioning, and missing-file recovery.

## Context

Part of **Epic 7 — LUTs as an optional Look stage**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Keep stable file and derived LUT identifiers.
- Resolve asynchronously after library scans without blanking the image.
- Represent None and zero intensity as identity.
- Surface missing/replaced LUTs once per relevant state change.

## Acceptance criteria

- [x] No LUT and 0% LUT produce the neutral non-LUT path.
- [x] Persisted file LUTs resolve after relaunch and folder restore.
- [x] Missing LUTs render safely without silently discarding the stored reference.
- [x] Replaced cube contents invalidate the filter/render caches.

## Verification

- Extend LUT ID, cache invalidation, missing-file, and persistence tests.

## Out of scope

- Embedding third-party LUT binaries into edit records.

### Comment — codex @ 2026-09-01T13:35:02.360Z

Implemented in commit 8196f39. Hardened LUTSettings Codable/identity handling for absent IDs, zero/non-finite/out-of-range intensity, canonicalized file IDs, made fresh library scans supersede retained saved LUTs, re-render after asynchronous resolution, report missing references once without discarding stored IDs, and flush LUT-dependent preview/filter caches on rescans. Added LUT ID, persistence-shape, missing-file, replacement, async resolution, and cache invalidation regressions. Verification: swift test (468 passed, 25 expected skips), swift build -c release, git diff --check, and dg validate passed; validate reports only pre-existing runner-model and LUMO-040 context warnings.

### Comment — claude @ 2026-09-01T13:38:35.324Z

Counterpoint verification (independent, post-human-review) — PASS, no blockers.

Scope reviewed: commit 8196f39 (LUTSettings identity/Codable hardening, CubeLUT.canonicalPath, RenderEngine.invalidateLUTCache, AppViewModel LUT resolution/status plumbing) plus the accompanying test additions.

Checks performed:
- Read the full diff against Sources/LumoKit/Models/{LUTSettings,CubeLUT,RenderEngine}.swift and ViewModels/AppViewModel.swift.
- Verified the `intensity { didSet { ... } }` self-reassignment is not recursive and does not fire during `init` (confirmed empirically: Swift property observers are skipped during a type's own initializer and do not re-trigger from a single reassignment inside didSet) — normalization is correctly idempotent either way.
- Verified the `resolvedLUT` priority swap (library scan wins over the derived registry) cannot regress the save flow: `adoptSavedLUT` re-parses the saved file through `CubeLUT(url:)`, which now canonicalizes identically to what a rescan would produce, so registry and post-scan library entries agree on ID and content.
- Verified `onScanned`'s new branch only calls `refreshLUTResolutionStatus()`/re-renders after `isScanning` is already false and `allLUTs` already published (checked `LUTLibrary.scan`), so no race against a still-running scan.
- Verified `previewCache.removeAll()` on every LUT rescan is a (harmless) belt-and-suspenders flush, not a masked correctness bug: `previewCacheKey` already includes `lutFingerprint`, so a resolved-vs-unresolved LUT naturally produces different cache keys. Flagged only as a minor, non-blocking performance note below — not worth a fix given it only fires on infrequent LUT-folder rescans/derived-LUT saves.
- Ran `swift test` — 468 passed, 25 expected skips, 0 failures (matches the implementer's report).
- Ran `swift build -c release` — succeeds (only pre-existing, unrelated `CIKernel`/`CIColorKernel` deprecation warnings).
- Ran `git diff --check` — clean.

Non-blocking observation (not filed as a ticket — too minor/speculative to warrant a backlog item): `invalidateLUTCache()` now also clears the entire `previewCache` on every LUT-folder rescan, including previews for documents that don't reference any LUT. Given rescans are infrequent (folder change, derived-LUT save) this is an acceptable trade of a little redundant re-rendering for simplicity, and matches the code's own comment about avoiding a race rather than chasing precision.

No blockers found. Acceptance criteria checked off. Moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
