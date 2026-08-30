---
id: LUMO-035
title: Epic 6 — Photographic effects
type: feature
status: backlog
priority: high
labels:
  - mvp
  - epic
  - epic:effects
  - phase:6
created: 2026-08-30T18:30:28.908Z
updated: 2026-08-30T18:31:55.364Z
depends_on:
  - LUMO-036
  - LUMO-037
  - LUMO-038
  - LUMO-039
order: p7777773
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
