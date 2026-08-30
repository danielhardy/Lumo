---
id: LUMO-051
title: Define durable export options and format capabilities
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:export
  - phase:9
created: 2026-08-30T18:30:34.634Z
updated: 2026-08-30T18:30:51.733Z
depends_on:
  - LUMO-012
  - LUMO-008
estimate: 5
order: zt
board: product
---

## Objective

Model output format, quality, full size/long edge, color space, filename policy, destination, and metadata behavior without UI dependencies.

## Context

Part of **Epic 9 — Reliable full-resolution export**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Retain JPEG, 16-bit TIFF, and PNG; enable HEIF only where encoding is clean and testable.
- Define resize semantics with no accidental upscaling by default.
- Enumerate supported color spaces and bit-depth/alpha constraints per format.
- Validate combinations before an export begins.

## Acceptance criteria

- [ ] Invalid format/bit-depth/color/alpha combinations fail with actionable errors.
- [ ] Long-edge resizing preserves aspect ratio and orientation.
- [ ] Defaults produce full-size high-quality output.
- [ ] Options are Sendable and testable independently of panels.

## Verification

- Add capability matrix, validation, sizing, and default tests.

## Out of scope

- Print layouts.
- Arbitrary ICC profile editing unless supported cleanly.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
