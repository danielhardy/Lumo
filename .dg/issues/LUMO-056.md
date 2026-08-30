---
id: LUMO-056
title: Create the curated image-quality validation matrix and rubric
type: task
status: backlog
priority: high
labels:
  - mvp
  - epic:quality
  - phase:10
created: 2026-08-30T18:30:36.467Z
updated: 2026-08-30T18:30:53.673Z
depends_on:
  - LUMO-028
  - LUMO-034
  - LUMO-039
  - LUMO-043
estimate: 5
order: zzq
board: product
---

## Objective

Build a durable non-redistributable/local test-set process and review rubric covering the scenes named in the concept.

## Context

Part of **Epic 10 — Image quality, performance, and MVP release gate**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Cover clipping highlights, deep shadows, underexposure, high ISO, skin, foliage, reds, sky, sunset, mixed WB, HDR, and haze.
- Define consistent comparison captures against Apple Photos, Lightroom, and camera JPEG where available.
- Record expected behavior for every major adjustment without demanding pixel matching.

## Acceptance criteria

- [ ] Every required scene and major control has a review entry.
- [ ] Licensing/privacy rules prevent accidental fixture redistribution.
- [ ] Reviewers can reproduce comparisons from documented steps.
- [ ] Failures become scoped dg bugs rather than undocumented taste notes.

## Verification

- Complete one baseline review pass and attach summarized results/approved sample assets.

## Out of scope

- Automated aesthetic scoring.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
