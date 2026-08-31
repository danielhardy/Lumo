---
id: LUMO-059
title: Run fault-recovery and end-to-end MVP release acceptance
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:quality
  - phase:10
created: 2026-08-30T18:30:37.650Z
updated: 2026-08-31T14:24:39.620Z
depends_on:
  - LUMO-058
  - LUMO-056
  - LUMO-049
  - LUMO-053
  - LUMO-010
  - LUMO-043
estimate: 5
order: zzx8
board: product
---

## Objective

Prove the Definition of Done and safe failure behavior from a clean install through relaunch and export.

## Context

Part of **Epic 10 — Image quality, performance, and MVP release gate**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Exercise missing/moved sources, stale bookmarks, corrupt edits, missing LUTs, unsupported files, disk-full/write denial, cancellation, and app restart.
- Walk all 18 Definition of Done outcomes from the concept.
- Verify no explicitly excluded V2 capability slipped into the critical path.
- Produce concise release notes, known limitations, and follow-up tickets.

## Acceptance criteria

- [ ] The complete shoot→open→cull→edit→copy→select→export workflow passes on a clean profile.
- [ ] Every tested fault yields recovery or a clear non-destructive error.
- [ ] All required automated tests/builds are green.
- [ ] Known limitations are explicit and no critical/urgent blocker remains open.

## Verification

- Run clean-profile manual acceptance, full tests, debug/release builds, and CI.

## Out of scope

- AI masks, healing, HDR/panorama merge, cloud sync, tethering, mobile, plugins, or catalog import.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
