---
id: LUMO-035
title: Epic 6 — Photographic effects
type: feature
status: done
priority: high
labels:
  - mvp
  - epic
  - epic:effects
  - phase:6
created: 2026-08-30T18:30:28.908Z
updated: 2026-09-01T05:20:05.106Z
depends_on:
  - LUMO-036
  - LUMO-037
  - LUMO-038
  - LUMO-039
order: y
board: product
---

## Objective

Deliver distinct Texture, Clarity, Dehaze, advanced Vignette, and deterministic photographic Grain without compromising responsiveness.

## MVP outcome

- [ ] The three detail/atmosphere controls are perceptually distinct.
- [ ] Vignette and grain expose all specified subordinate controls.
- [ ] Grain is stable across rerenders and scales correctly at export.

## Child tickets

- LUMO-036 — Implement distinct Texture, Clarity, and Dehaze stages
- LUMO-037 — Implement advanced post-crop vignette
- LUMO-038 — Implement deterministic resolution-aware photographic grain
- LUMO-039 — Ship Effects inspector sections and quality gate

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T05:20:05.104Z: Epic verified complete: Texture, Clarity, Dehaze, advanced post-crop Vignette, deterministic resolution-aware Grain, and the Effects inspector are implemented across child tickets LUMO-036 through LUMO-039. Full swift test passed (462 passed, 25 expected skips); swift build -c release and git diff --check passed. Effects pipeline, persistence, preview/export parity, reset/undo, and interactive rendering coverage are green.
