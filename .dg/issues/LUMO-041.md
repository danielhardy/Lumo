---
id: LUMO-041
title: Harden optional LUT identity and resolution across persisted edits
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:lut
  - phase:7
created: 2026-08-30T18:30:30.848Z
updated: 2026-08-30T18:30:48.483Z
depends_on:
  - LUMO-008
  - LUMO-014
estimate: 3
order: tipx4bil
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

- [ ] No LUT and 0% LUT produce the neutral non-LUT path.
- [ ] Persisted file LUTs resolve after relaunch and folder restore.
- [ ] Missing LUTs render safely without silently discarding the stored reference.
- [ ] Replaced cube contents invalidate the filter/render caches.

## Verification

- Extend LUT ID, cache invalidation, missing-file, and persistence tests.

## Out of scope

- Embedding third-party LUT binaries into edit records.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
