---
id: LUMO-032
title: Implement the eight-channel HSL Color Mixer
type: task
status: done
priority: high
labels:
  - mvp
  - epic:color
  - phase:5
created: 2026-08-30T18:30:27.784Z
updated: 2026-08-31T20:48:35.237Z
depends_on:
  - LUMO-024
estimate: 8
order: a0
board: product
commits:
  - ea79753
---

## Objective

Add Hue, Saturation, and Luminance controls for Red, Orange, Yellow, Green, Aqua, Blue, Purple, and Magenta.

## Context

Part of **Epic 5 — White balance, mixer, and color grading**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define Codable fixed-channel model and ranges.
- Implement hue-weighted GPU kernel/filter with smooth overlaps and hue wraparound.
- Avoid seams, hard channel boundaries, and CPU loops.
- Include state in hashing, undo, copy/paste, and persistence.

## Acceptance criteria

- [ ] Each channel primarily affects its intended hue neighborhood with smooth falloff.
- [ ] Hue wraparound at red is continuous.
- [ ] Neutral mixer is identity and results are deterministic.
- [ ] Interactive performance meets the common-control target on representative hardware.

## Verification

- Add hue-wheel locality, wraparound, neutral, determinism, and preview/export tests.

## Out of scope

- Targeted adjustment eyedropper.

### Comment — codex @ 2026-08-31T20:48:18.248Z

### Comment — codex @ 2026-08-31T20:48:35.050Z

Implemented in commit ea79753. Added Codable/Equatable/Sendable eight-channel ColorMixerAdjustments with finite clamped Hue/Saturation/Luminance ranges, nested ColorAdjustments persistence/hash/identity integration, one reusable Core Image GPU HSL kernel with raised-cosine overlaps and circular red wraparound, premultiplied-alpha handling, and cache version bump. Added locality, overlap, wraparound, neutral, determinism, undo, persistence, and preview/export parity tests. Verification: swift test passed (405 executed, 21 skipped), swift build -c release passed, git diff --check passed, dg validate OK with only pre-existing warnings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T20:48:35.235Z: Verified LUMO-032: eight-channel HSL mixer model and shared GPU kernel pass locality, smooth overlap, red wraparound, neutral identity, determinism, undo/persistence, and preview/export parity checks. swift test (405/0 fail, 21 expected skips), release build, git diff --check, and dg validate all passed.
