---
id: LUMO-024
title: Define the Light adjustment model, ranges, order, and migration
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:light
  - phase:4
created: 2026-08-30T18:30:24.972Z
updated: 2026-08-31T19:25:45.859Z
depends_on:
  - LUMO-012
estimate: 3
order: n
board: product
commits:
  - 0ddada9
---

## Objective

Create a coherent Light model over the existing adjustment nodes without discarding working render code.

## Context

Part of **Epic 4 — Photographic Light controls**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define Exposure, Contrast, Highlights, Shadows, Whites, Blacks, and tone curve values with photographer-facing ranges.
- Specify neutral values, clamping, Codable migration, edit hash, and pipeline position.
- Map or migrate current exposure/contrast/highlight/shadow documents deliberately.

## Acceptance criteria

- [ ] Neutral Light is a true render identity.
- [ ] Old documents decode without losing their existing look.
- [ ] All values are finite, clamped, Codable, Equatable, and Sendable.
- [ ] Pipeline order and version impact are documented.

## Verification

- Add neutral, range, migration, hash, and Codable tests.

## Out of scope

- Local masks.
- Exact Adobe mathematics.

### Comment — codex @ 2026-08-31T19:25:06.126Z

Implemented in commit 0ddada9. Added LightAdjustments with photographer-facing ranges, finite/clamped Codable values, normalized versioned master RGB curve, neutral identity, and deterministic editHash coverage. Integrated Light before inherited ordered adjustments in RenderPipeline; kept legacy exposure/contrast/highlight/shadow nodes unchanged when light is absent, preserving old document looks. Documented pipeline order and cache-version impact in docs/LIGHT_MODEL.md. Checks: swift test (359 passed, 20 expected skips), swift build -c release, dg validate (OK; only pre-existing warnings).

### Comment — codex @ 2026-08-31T19:25:45.856Z

Final post-commit verification: swift test passed 360 tests with 20 expected RAW-environment skips and 0 failures. The committed tree is clean outside pre-existing DispatchGraph metadata changes.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T19:25:09.763Z: Defined and integrated the Light adjustment model with tested neutral identity, ranges, Codable migration, edit hashing, and documented pipeline/cache versioning.
