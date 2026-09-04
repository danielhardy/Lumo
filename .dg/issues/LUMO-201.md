---
id: LUMO-201
title: User-facing Masking UI (Select Subject/Person/Background/Face)
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:56.274Z
updated: 2026-09-04T14:34:44.969Z
depends_on:
  - LUMO-186
  - LUMO-188
  - LUMO-189
  - LUMO-190
  - LUMO-191
order: zzzzzzq
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Views/MaskingPanel.swift` (+ supporting view model)
**Depends on:** LUMO-186, LUMO-188, LUMO-189, LUMO-190, LUMO-191
**Epic:** LUMO-181 — see mask-first architecture note below

## 1. Problem

This is the payoff ticket for the whole mask-first restructure: a user-facing Masking panel that
lets someone select **Subject**, **Person**, **Background**, or **Face** as the target of a local
adjustment — by calling the *exact same* `SemanticMaskProviding`/`RegionMask` infrastructure Auto
already uses (LUMO-200), just at a higher `MaskQuality`. This ticket is **not** blocked on Auto
shipping — it depends directly on the mask providers (LUMO-188/189/190/191) and `MaskOperations`
(LUMO-186), not on `AutoLightEngine`. If Auto (LUMO-200) hasn't landed yet when this is picked up,
proceed anyway; note the one shared risk explicitly: if this ticket discovers `RegionMask`/
`SemanticMaskProviding`'s shape is awkward for interactive use, that's a signal the foundation
(LUMO-184) needs a follow-up fix — not a reason to build a parallel mask path here.

## 2. Requirement (acceptance criteria)

1. A masking panel (scope for v1: selection only, not painting/brushing — see LUMO-202 for
   full-resolution refinement) presenting the semantic kinds a photo actually has available
   (per `AnalysisQuality`/whichever masks succeeded): Subject, Person, Background, Face — each
   requested via:
   ```swift
   let mask = maskService.mask(for: .subject, image: image, quality: .preview)
   ```
   at `.preview` quality (not `.analysis` — the UI needs a visibly higher-fidelity mask than Auto
   does for its invisible statistics-only use; not `.render` yet either — that's LUMO-202's job).
2. Selecting a kind shows a visual overlay of the mask (reuse LUMO-203's debug-overlay rendering
   logic if it exists by this point, or build the minimal version here and let LUMO-203 reuse it —
   whichever lands first should be the one the other reuses, not duplicate).
3. Basic combination via `MaskOperations` (LUMO-186) — at minimum, invert (e.g. "everything except
   the subject") — full paint/brush/feather refinement UI is out of scope for this ticket (that's
   local-adjustment rendering, a larger UI effort likely warranting its own follow-up tickets
   beyond LUMO-202's scope, which only covers the mask-quality upgrade pipeline, not the paint
   tool itself).
4. Masks requested here are cached through the same `MaskStore` (LUMO-185) Auto uses — selecting
   "Subject" in the UI after Auto already ran should be fast (cache hit), not a fresh Vision call.
5. No new Vision/CoreImage code in this ticket — it only calls `PhotoAnalysisCoordinator.mask(...)`
   (LUMO-195) and `MaskOperations` (LUMO-186).
6. Swift 6 clean; `@MainActor` for the view layer is expected, calling into the `async` coordinator
   rather than blocking.

## 3. Implementation notes

- This ticket is explicitly a thin UI layer proving the foundation is real and reusable, not a
  full masking product. Resist scope creep toward local-adjustment painting — that's a
  substantially larger UI/rendering effort and, per the user's own framing of this plan, doesn't
  need to be complete before Auto ships.
- If a given photo has no faces/no clear foreground (e.g. a landscape), the panel should degrade
  gracefully — show only the kinds that are actually available, same `AnalysisQuality`-driven
  degradation Auto already follows.

## 4. Where to look

- `Sources/LumoKit/Views/` — existing view conventions.
- LUMO-195's `PhotoAnalysisCoordinator.mask(...)` — the entry point this UI calls.
- LUMO-186's `MaskOperations` — combination logic.

## 5. Testing

- Smoke test: panel constructs without crashing given a mock `PhotoAnalysisCoordinator`.
- Manual verification per CLAUDE.md's UI-change guidance: run the app, open a photo with a clear
  subject and a face, select each available kind, and confirm the overlay matches the underlying
  mask.
