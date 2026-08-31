---
id: LUMO-018
title: Introduce stable PhotoAsset and library metadata records
type: task
status: verification
priority: urgent
labels:
  - mvp
  - epic:library
  - phase:3
created: 2026-08-30T18:30:23.027Z
updated: 2026-08-31T14:33:49.991Z
depends_on:
  - LUMO-004
  - LUMO-006
estimate: 5
order: a0
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
