---
id: LUMO-006
title: Version the durable edit schema and rendering pipeline identity
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:18.849Z
updated: 2026-08-31T03:09:06.404Z
depends_on:
  - LUMO-004
estimate: 3
order: y
board: product
---

## Objective

Extend the existing EditDocument seam with explicit schema and pipeline-version semantics before persistent records are written.

## Context

Part of **Epic 1 — Durable per-photo edit domain**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define how current schema version and render pipeline version are encoded and migrated.
- Preserve Codable, Equatable, Sendable value semantics and neutral identity.
- Reject future unsupported versions without overwriting them.

## Acceptance criteria

- [ ] Persisted records contain schema and pipeline versions.
- [ ] Missing fields migrate to documented neutral defaults.
- [ ] Newer unsupported records fail safely and remain untouched.
- [ ] Cache identity can include the pipeline version.

## Verification

- Add Codable round-trip, old-record migration, and future-version rejection tests.

## Out of scope

- Database selection or UI.
- Reordering released pipelines without a migration.

### Comment — codex @ 2026-08-31T03:06:47.207Z

Implemented and verified in commit a556bb8. EditDocument now persists explicit schemaVersion and pipelineVersion fields, migrates legacy version/missing fields to current supported versions and neutral edit defaults, and rejects newer schema or render-pipeline records without mutation. RenderPipeline exposes its current identity and LUTFilterCache keys include pipelineVersion. Added Codable migration/rejection and cache-identity tests. Verification: swift test passed (311 tests, 20 expected skips, 0 failures); swift build passed; swift build -c release passed; dg validate passed.

### Comment — claude @ 2026-08-31T03:09:03.859Z

Independent verification (counterpoint pass) — PASS.

Reviewed commit a556bb8 against acceptance criteria:
- Persisted records carry explicit schemaVersion + pipelineVersion fields (EditDocument.swift).
- Missing-field migration verified: legacy unversioned/`version`-only records decode to documented neutral defaults (testAbsentFieldsFallBackToDefaults, testLegacyRecordMigratesToExplicitVersionsAndNeutralDefaults).
- Newer unsupported schema/pipeline versions are rejected via DecodingError.dataCorrupted without mutating the source bytes (testNewerSchemaVersionIsRejected, testNewerPipelineVersionIsRejected).
- LUTFilterCache key now includes pipelineVersion, giving cache identity pipeline-version awareness (LUTFilterCacheTests).
- Codable/Equatable/Sendable value semantics preserved; RenderPipeline.currentVersion is the single source of truth threaded through EditDocument and the cache.

Finding (fixed in place, localized): EditDocument carried two unused compatibility shims — a `version` computed property and a `renderPipelineVersion` computed property plus an `init(version:)` overload — added speculatively for callers that don't exist anywhere in the tree (grepped Sources/ and Tests/, zero references beyond their own declarations). Per CLAUDE.md's guidance against back-compat hacks for scenarios that can't happen, removed all three in commit 19e42a3. No behavior change; all 311 tests still pass.

Checks re-run: `swift build` OK, `swift test` — 311 tests, 20 skipped, 0 failures, `swift build -c release` OK, `dg validate` OK (pre-existing unrelated warnings only).

Verification commit: 19e42a3 "Remove unused compatibility shims from EditDocument".

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
