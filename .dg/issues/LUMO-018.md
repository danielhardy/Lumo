---
id: LUMO-018
title: Introduce stable PhotoAsset and library metadata records
type: task
status: review
priority: urgent
labels:
  - mvp
  - epic:library
  - phase:3
created: 2026-08-30T18:30:23.027Z
updated: 2026-08-31T14:48:09.002Z
depends_on:
  - LUMO-004
  - LUMO-006
estimate: 5
order: a0
board: product
branch: agent/lumo-018
commits:
  - 0d14f3d
---

## Objective

Replace session UUID-only collection items with stable, Sendable asset records suitable for persistence, caching, selection, and relinking.

## Context

Part of **Epic 3 — Folder library and rapid culling**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Represent stable ID, source/bookmark, filename/type, dimensions, capture date, camera/lens metadata, rating, flag, and thumbnail state.
- Define source fingerprint behavior for moved or replaced files.
- Keep immutable source identity separate from mutable library/edit state.

## Acceptance criteria

- [ ] The same unchanged file receives the same identity across relaunch.
- [ ] Replaced content does not silently reuse stale render/edit caches.
- [ ] Photo metadata and culling state are value-based and Codable/Sendable.
- [ ] Photos-imported data has a documented durable identity policy.

## Verification

- Add stable-ID, collision, changed-file, and Codable tests.

## Out of scope

- Content-addressing entire RAW files on every scan.
- Albums beyond the opened folder.

### Comment — codex @ 2026-08-31T14:33:44.361Z

Implemented in commit 0961319. Added Codable/Sendable PhotoAsset, PhotoAssetID, PhotoAssetSource, bounded PhotoSourceFingerprint, metadata and mutable culling/thumbnail state; replaced ImageCollection's session UUID item IDs with stable asset IDs; documented the Photos data-only SHA-256 identity policy; added stable-ID, collision, moved/replaced-source, Codable, and collection rescan tests. Verification: swift build, swift test (314 executed, 20 expected skips, 0 failures), swift build -c release, dg validate OK (pre-existing warnings only).

### Comment — claude @ 2026-08-31T14:45:46.389Z

## Verification report (counterpoint agent, independent pass)

**Scope reviewed:** commit 0961319 (PhotoAsset/PhotoAssetID/PhotoAssetSource/PhotoSourceFingerprint,
ImageCollection integration, ImageMetadata Codable/Sendable conformance, PhotoAssetTests).

**Checks run:**
- `swift build` — clean.
- `swift test` — 314 executed, 20 expected skips, 0 failures (matches prior claim).
- `swift build -c release` — clean.
- `dg validate` — OK, pre-existing warnings only.
- `swift test --filter PackageSettingsTests` — Swift 6 mode intact, zero concurrency escape hatches.

**Findings:**
- Correctness: identity/fingerprint/matching semantics check out against the acceptance criteria —
  same-file identity is stable across rebuilds, distinct files with identical bytes don't collide,
  in-place edits change the fingerprint/cache key while a same-volume move preserves it, and the
  asset/library-state split round-trips through Codable. `ImageCollection` items now carry stable
  `PhotoAssetID`s across rescans (covered by `testCollectionItemsUseStableAssetIDs`).
  Acceptance criterion 4 (documented Photos-imported identity policy) is covered in the README diff.
- No blockers found.
- Minor maintainability nit (fixed directly, localized/testable): `PhotoAsset` exposed two identical
  computed properties, `bookmarkData` and `bookmark`, both forwarding to `source.bookmarkData`.
  `bookmark` was unused anywhere in the codebase — removed in commit 0d14f3d. Re-ran the full suite
  and targeted PhotoAssetTests after the change; still 314/0 and green.

**Verdict:** PASS. No child tickets needed — the one issue found was small enough to fix inline per
the action rules. Moving to `done`.

### Comment — codex @ 2026-08-31T14:45:49.485Z

Automatic merge into `main` failed: Auto-merging README.md
Auto-merging Sources/LumoKit/Models/ImageCollection.swift
CONFLICT (content): Merge conflict in Sources/LumoKit/Models/ImageCollection.swift
Automatic merge failed; fix conflicts and then commit the result.

### Comment — claude @ 2026-08-31T14:48:08.784Z

## Blocker found: automated merge to main failed

`dg issue complete` attempted to auto-merge `agent/lumo-018` into `main` and hit a real conflict in
`Sources/LumoKit/Models/ImageCollection.swift` (plus a smaller one in `README.md`). Root cause: since
this branch's merge-base (`50f80a3`), `main` picked up a sibling rework of `ImageCollection`'s
thumbnail pipeline (`ee28124` "Integrate prioritized thumbnail scheduling`, not an ancestor of
`50f80a3`) that touches the same code region as this issue's `PhotoAsset`-based `Item` rework. Two
independent reworks of the same file — reconciling them is a real three-way merge decision, not a
mechanical or localized fix, so it's outside this verification pass's action rules.

The code itself passed independent verification (build/test/release/`dg validate` all green, 314/0
failures, one small dead-code fix applied in `0d14f3d`) — the blocker is integration, not
correctness. Filed **LUMO-064** (urgent, depends on this issue) to reconcile the merge. Moving this
issue back to `review` until LUMO-064 lands `agent/lumo-018` on `main`.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T14:45:49.074Z: Independent verification pass: build/test/release/dg validate all green (314 tests, 0 failures), matches prior claim. Removed one dead duplicate accessor (PhotoAsset.bookmark) as a localized fix. No blockers.
