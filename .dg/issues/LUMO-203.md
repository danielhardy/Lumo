---
id: LUMO-203
title: Debug analysis and mask visualization overlay
type: task
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:57.189Z
updated: 2026-09-04T14:34:45.601Z
depends_on:
  - LUMO-194
order: zzzzzzx
board: product
---

**Type:** Task
**Component:** new debug/inspector UI (`Sources/LumoKit/Views/` — exact location TBD)
**Depends on:** LUMO-194
**Epic:** LUMO-181 — see original proposal §42

## 1. Problem

When Auto (or the Masking UI) makes a bad call, the only way to understand why is to reverse-
engineer it through logs. A debug overlay that shows exactly what every mask provider and analyzer
saw is one of the highest-leverage tools for iterating on this subsystem.

## 2. Requirement (acceptance criteria)

1. A developer-only view (gated similarly to any existing dev-only affordance, or a new debug menu
   item) that, given the current photo's `PhotoAnalysis` (LUMO-194) and raw `RegionMask`s from
   `MaskStore`/`PhotoAnalysisCoordinator` (LUMO-195), can show/toggle:
   - Every semantic mask (subject, background, person, face(s), foreground instances) as an
     overlay, drawn via `NormalizedRect`/`NormalizedMask` (LUMO-183/184) directly — this doubles
     as a live correctness check on the coordinate-conversion code.
   - Primary subject region + confidence (once LUMO-197 exists).
   - Global histogram (reuse Lumo's existing histogram UI if one exists).
   - `AnalysisQuality` and `AnalysisTimings`.
   - Once LUMO-200 exists: the Auto rationale for the current photo.
2. No performance cost when the overlay isn't visible — requests analysis/masks on demand, never
   eagerly.
3. Swift 6 clean; `@MainActor` view layer calling into the `async` coordinator.

## 3. Implementation notes

- This can be genuinely rough/utilitarian. If LUMO-201's Masking UI already built overlay-drawing
  logic by the time this lands, reuse it rather than duplicating (see LUMO-201 §2.2's note on
  whichever lands first being the one reused).
- If LUMO-197/200 haven't landed yet when this is picked up, ship without those panels and leave
  a `// TODO` — don't block on them.

## 4. Where to look

- `Sources/LumoKit/Views/` — existing view conventions.
- LUMO-183/184's coordinate/mask types — what the overlay draws.
- LUMO-201's Masking UI, if it landed first.

## 5. Testing

- Smoke test: view constructs with a synthetic `PhotoAnalysis` without crashing.
- Manual verification against a real photo with a clear subject, per CLAUDE.md's UI-change
  guidance.
