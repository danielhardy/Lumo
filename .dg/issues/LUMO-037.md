---
id: LUMO-037
title: Implement advanced post-crop vignette
type: task
status: done
priority: high
labels:
  - mvp
  - epic:effects
  - phase:6
created: 2026-08-30T18:30:29.489Z
updated: 2026-09-01T04:52:09.882Z
depends_on:
  - LUMO-024
estimate: 5
order: zzzh
board: product
---

## Objective

Add Amount, Midpoint, Roundness, Feather, and Highlights after LUT and before output transform as versioned pipeline behavior.

## Context

Part of **Epic 6 — Photographic effects**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define normalized scale-independent model.
- Implement GPU mask/compose preserving bright highlights according to the Highlights parameter.
- Account for crop/output geometry deterministically.

## Acceptance criteria

- [ ] Every subordinate parameter has an independent visible effect.
- [ ] Neutral amount is identity.
- [ ] Feathering is smooth, roundness respects aspect ratio, and no extent changes occur.
- [ ] Preview/export composition matches for the same crop.

## Verification

- Add geometry, parameter-independence, identity, and parity tests.

## Out of scope

- Lens-profile vignette correction.

### Comment — codex @ 2026-09-01T04:50:19.031Z

Implemented in commit 6b533cc. Added Codable/clamped VignetteAdjustments (Amount, Midpoint, Roundness, Feather, Highlights), a GPU Core Image radial mask with aspect-ratio-aware post-crop extent geometry and highlight preservation, and placed vignette after LUT before output. Added identity, parameter-independence, extent/aspect, highlight, ordering, Codable, and preview/export parity coverage; documented pipeline/cache version 12. Verification: swift test (448 passed, 24 expected skips), swift build -c release, git diff --check, dg validate (known unrelated runner/context warnings only).

### Comment — claude @ 2026-09-01T04:52:07.916Z

Verification report (counterpoint agent, independent of human review):

Scope reviewed: commit 6b533cc (VignetteAdjustments model, RenderPipeline vignette stage/kernel, docs, tests).

Checks run:
- swift build: clean.
- swift test: 448 passed, 24 expected skips (RAW-fixture-dependent), 0 failures.
- git status --porcelain: clean aside from pre-existing DispatchGraph metadata churn (unrelated to this issue).

Code review findings:
- Vignette placement (after LUT, before output) matches the objective; applyVignette is invoked exactly once in the production buildImage path, and the applyEffects convenience wrapper (test-only caller) composes the same order.
- Kernel math checked by hand: Lp-norm radius with exponent = 3 - roundness (clamped [-1,1]) gives p in [2,4], matching the "positive Roundness rounds corners" doc comment; smoothstep edge0/edge1 ordering is safe for all clamped inputs (edge0 < edge1 always); highlight preservation correctly unpremultiplies before computing luminance.
- Geometry guards (finite/positive width & height) correctly avoid the kernel on degenerate/infinite extents.
- isIdentity gating on Amount only (subordinate params stay live for later re-enable) matches the documented model and the persisted-shape rationale in code comments.
- No dead code or correctness bugs found. One cosmetic no-op noticed (`max(0.015, 0.08 + feather*0.42)` — the 0.015 floor is unreachable since 0.08 alone always exceeds it) — not worth a fix, doesn't affect behavior.
- No UI wiring for the new Vignette controls, but this matches the existing precedent: Texture/Clarity/Dehaze (same Effects model) are also pipeline-only with no inspector UI yet, so this isn't a regression introduced by this change.
- Docs (EFFECTS_MODEL.md, LIGHT_MODEL.md) and cache version bump (11→12) are consistent with the code change.

Verdict: PASS. No blockers, no localized fixes needed, no new backlog tickets warranted.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
