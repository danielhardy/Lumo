---
id: LUMO-019
title: Build progressive cancellable folder ingestion and metadata loading
type: task
status: ready
priority: urgent
labels:
  - mvp
  - epic:library
  - phase:3
created: 2026-08-30T18:30:23.370Z
updated: 2026-08-31T14:24:14.325Z
depends_on:
  - LUMO-018
estimate: 5
order: n
board: product
---

## Objective

Publish useful assets incrementally while folder scanning and metadata extraction stay off the main actor.

## Context

Part of **Epic 3 — Folder library and rapid culling**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Scan supported formats recursively with deterministic ordering.
- Publish batches rather than waiting for the entire traversal.
- Separate cheap discovery from deferred dimensions/capture/camera metadata.
- Cancel cleanly on folder switch or rescan.

## Acceptance criteria

- [ ] Visible library content begins appearing before a large scan completes.
- [ ] Folder switching cannot mix results from two scans.
- [ ] Metadata parsing never blocks the main actor.
- [ ] Unsupported, unreadable, and disappearing files are skipped/reported without aborting the scan.

## Verification

- Add incremental delivery, cancellation, ordering, and failure-isolation tests.

## Out of scope

- Filesystem watcher synchronization unless needed for MVP refresh.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
