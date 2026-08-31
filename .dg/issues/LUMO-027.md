---
id: LUMO-027
title: Implement a versioned RGB tone curve model and renderer
type: task
status: done
priority: high
labels:
  - mvp
  - epic:light
  - phase:4
created: 2026-08-30T18:30:26.080Z
updated: 2026-08-31T19:54:34.195Z
depends_on:
  - LUMO-024
estimate: 5
order: a0
board: product
commits:
  - 4ac9a3a
---

## Objective

Add a compact, editable tone curve with deterministic interpolation suitable for persistence and later UI editing.

## Context

Part of **Epic 4 — Photographic Light controls**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define ordered normalized control points and validation rules.
- Choose GPU-backed interpolation that is monotonic when the points are monotonic.
- Start with a master RGB curve; leave channel curves extensible if not shipped.
- Include curve state in hashes, copy/paste, undo, and persistence.

## Acceptance criteria

- [ ] Default diagonal is identity.
- [ ] Invalid/duplicate/out-of-range points normalize or fail predictably.
- [ ] A monotonic curve cannot create reversals due to interpolation.
- [ ] Preview and full-resolution renders agree within test tolerance.

## Verification

- Add model validation, interpolation, identity, monotonicity, and parity tests.

## Out of scope

- Parametric curve regions unless justified.
- Local curves.

### Comment — codex @ 2026-08-31T19:52:28.168Z

Implemented in commit e265a70. Added normalized/versioned master RGB curve interpolation with deterministic duplicate/out-of-range handling, GPU-backed CIColorCube rendering, pipeline cache-version bump, and Codable/hash coverage. Added identity, monotonicity, forward-schema rejection, render, and preview/export parity tests. Verification: swift test (373 passed, 20 expected skips), swift build -c release, git diff --check, dg validate.

### Comment — claude @ 2026-08-31T19:54:31.397Z

Independent verification: PASS, with one performance fix applied.

**Reviewed:** commit e265a70 (LightToneCurve model + applyToneCurve GPU color-cube stage, RenderPipeline.cacheVersion 5→6).

**Correctness/model checks (all held):**
- Default diagonal is identity (`LightToneCurve.identity`, `isIdentity`); `testToneCurveRenderIsUnchangedAtItsIdentity` confirms it's an exact render no-op.
- Duplicate/out-of-range/non-finite points normalize predictably: per-point clamp to 0...1 with NaN→fallback in `LightCurvePoint.init`, dictionary last-write-wins + forced endpoints in `LightToneCurve.normalized`.
- Piecewise-linear `value(at:)` cannot overshoot between monotonic points (no spline ringing); `isMonotonic` lets callers check without rewriting points, matching the "preserve full control-point space" decision documented in the property's doc comment.
- Curve state participates in Codable, `editHash`, and the render pipeline cache version bump (v6) — `testEditHashIsStableAndIncludesLightState` and the cache-version doc/const both updated together.
- Forward-schema versions are rejected with a clear decode error (`testToneCurveRejectsANewerSchemaVersion`).
- Preview/full-res parity: `RenderEngineTests` includes the tone curve in its preview/export parity document; no separate resolution-dependent state (the curve interpolates in normalized 0...1 space and is sampled into a resolution-independent cube).

**Performance issue found and fixed (commit 4ac9a3a):** `applyToneCurve` built the 64³ RGBA cube by calling `curve.value(at:)` inside the nested r/g/b loop for every channel, even though all three channels share one transfer function. That resampled green 64x more than necessary (4,096 calls instead of 64) and red 4,096x more (262,144 calls instead of 64) — ~266K linear-scan interpolation calls per non-identity-curve render instead of 64. Since `applyLight` runs on every render pass, including interactive preview drags, this is on the hot path. Fix: sample the 64 lattice positions into a small table once, then index into it for all three channels. Pure performance change, no behavior difference — confirmed identical output via the existing pixel-parity tests.

**Checks run:**
- `swift test`: 373 tests, 20 expected skips, 0 failures (matches the implementer's baseline).
- `swift build -c release`: passed.
- `git diff --check`: clean.
- `dg validate`: OK, only pre-existing warnings (agents.pickup.runner model name, LUMO-023 context completeness).

No blocking findings, no backlog children filed — the fix was small and localized enough to apply directly per the verification action rules.

Clearing lease and moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T19:54:34.009Z: Independent verification passed; fixed a redundant tone-curve sampling perf issue in the color-cube build (4ac9a3a).
