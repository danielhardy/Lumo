---
id: LUMO-039
title: Ship Effects inspector sections and quality gate
type: task
status: backlog
priority: medium
labels:
  - mvp
  - epic:effects
  - phase:6
created: 2026-08-30T18:30:30.238Z
updated: 2026-08-30T18:30:48.123Z
depends_on:
  - LUMO-036
  - LUMO-037
  - LUMO-038
  - LUMO-013
  - LUMO-009
estimate: 5
order: s2voha2r
board: product
---

## Objective

Expose all Effects controls with reset/undo behavior and validate performance and image quality before downstream UX polish.

## Context

Part of **Epic 6 — Photographic effects**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Add collapsible Texture/Clarity/Dehaze, Vignette, and Grain groups.
- Wire interactive/settled render behavior and gesture undo.
- Create representative hazy, high-detail, portrait, and high-ISO validation cases.

## Acceptance criteria

- [ ] Every specified parameter is editable, resettable, persistent, copyable, and undoable.
- [ ] Inspector remains responsive throughout rendering.
- [ ] Representative before/after samples pass the documented quality rubric.
- [ ] Common effects meet the interactive performance gate or have measured follow-up blockers.

## Verification

- Run model/pipeline tests and capture performance signposts on representative RAW files.

## Out of scope

- Local effects masks.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
