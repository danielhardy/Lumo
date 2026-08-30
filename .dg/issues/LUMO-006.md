---
id: LUMO-006
title: Version the durable edit schema and rendering pipeline identity
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:18.849Z
updated: 2026-08-30T18:30:38.604Z
depends_on:
  - LUMO-004
estimate: 3
order: 4bipx4bi
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
