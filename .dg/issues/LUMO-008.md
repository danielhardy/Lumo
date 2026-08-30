---
id: LUMO-008
title: Persist per-photo edit records with atomic recovery
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:19.524Z
updated: 2026-08-30T18:30:38.967Z
depends_on:
  - LUMO-007
estimate: 5
order: 5rcyk5rc
board: product
---

## Objective

Implement the simplest local edit store that safely survives relaunch without modifying source files.

## Context

Part of **Epic 1 — Durable per-photo edit domain**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Choose and document an internal JSON or lightweight database representation based on measured complexity.
- Key records by stable source identity and retain bookmark/relink information.
- Write atomically and preserve last-known-good data on corruption or interruption.
- Load asynchronously away from the main actor.

## Acceptance criteria

- [ ] Edits survive clean quit/relaunch and folder restoration.
- [ ] RAW and standard originals are byte-for-byte untouched.
- [ ] Missing, malformed, and partially written records fail safely with actionable status.
- [ ] Writes are atomic and migrations are testable.

## Verification

- Add persistence round-trip, corrupt-record, missing-source, and migration tests.
- Assert persistence I/O is not main-actor bound.

## Out of scope

- Cloud sync.
- A Lightroom-scale catalog.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
