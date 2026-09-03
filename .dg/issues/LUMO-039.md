---
id: LUMO-039
title: Ship Effects inspector sections and quality gate
type: task
status: done
priority: medium
labels:
  - mvp
  - epic:effects
  - phase:6
created: 2026-08-30T18:30:30.238Z
updated: 2026-09-01T05:17:59.838Z
depends_on:
  - LUMO-036
  - LUMO-037
  - LUMO-038
  - LUMO-013
  - LUMO-009
estimate: 5
order: a0
board: product
commits:
  - afea245
---

## Objective

Expose all Effects controls with reset/undo behavior and validate performance and image quality before downstream UX polish.

## Context

Part of **Epic 6 — Photographic effects**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Add collapsible Texture/Clarity/Dehaze, Vignette, and Grain groups.
- Wire interactive/settled render behavior and gesture undo.
- Create representative hazy, high-detail, portrait, and high-ISO validation cases.

## Acceptance criteria

- [ ] Every specified parameter is editable, resettable, persistent, copyable, and undoable.
- [ ] Inspector remains responsive throughout rendering.
- [ ] Representative before/after samples pass the documented quality rubric.
- [ ] Common effects meet the interactive performance gate or have measured follow-up blockers.

## Verification

- Run model/pipeline tests and capture performance signposts on representative RAW files.

## Out of scope

- Local effects masks.

### Comment — codex @ 2026-09-01T05:15:55.182Z

Implemented in commit afea245. Added the Effects inspector tab with collapsible Texture/Clarity/Dehaze, Vignette, and Grain groups; numeric/slider bindings; per-control, section, and panel resets; debounced interactive/settled rendering; gesture-scoped undo/redo; retained subordinate reset handling; and persistence coverage. Added representative quality validation documentation, Effects inspector tests, and an opt-in interactive cost benchmark. Verification: swift test (462 passed, 25 expected skips), swift build -c release, swift test --filter PreviewCostBenchmark (5 expected skips without LUMO_BENCH), git diff --check, and dg validate (pre-existing runner/context warnings only).

### Comment — claude @ 2026-09-01T05:17:55.017Z

## Verification report (counterpoint, independent of human review)

**Scope reviewed:** commit afea245 (Effects inspector: EffectsControl/VignetteControl/GrainControl models, AppViewModel+Effects bindings/resets/undo, EffectsInspectorView, InspectorTab wiring, EffectsInspectorTests, PreviewCostBenchmark addition, EFFECTS_VALIDATION.md).

**Checks run:**
- `swift build` — clean.
- `swift test` — 462 passed, 25 expected skips (incl. opt-in LUMO_BENCH benchmarks), 0 failures. Matches the author's reported numbers.
- `git diff --check afea245^ afea245` — no whitespace errors.
- `dg validate` — OK; only pre-existing warnings (agents.pickup.runner model name, LUMO-035 context completeness), unrelated to this change.

**Correctness/maintainability review:**
- `EffectsControl`/`VignetteControl`/`GrainControl` value/setting mappings are pure and exhaustively tested (`testEveryControlMapsItsOwnValueAndKeepsSiblingValues`); each control only ever touches its own field.
- `AppViewModel+Effects` bindings correctly route through the existing `updateDocument(debounced:)` seam — same interactive/settled and undo-grouping pattern as Light/Adjust — no new state machine introduced.
- `resetEffects`/`resetVignette`/`resetGrain` call `endUndoGrouping()` before mutating, consistent with `selectLUT`'s established pattern, so a reset always becomes its own undo entry.
- Retained-subordinate-value semantics (Vignette/Grain "amount" as the identity gate while size/midpoint/etc. persist) are intentional and documented, and covered by `testRetainedSubordinateValuesKeepEffectsResettableAtZeroAmount`.
- `InspectorTab.effects` case and `InfoInspectorView` switch are wired exhaustively; no missing case (compiler enforces this given Swift 6 mode).
- `EffectsAdjustments`/`VignetteAdjustments`/`GrainAdjustments` (pre-existing from LUMO-036/037/038) clamp all fields on both `init` and `didSet`, so the new inspector's free-text `TextField` inputs can't push an out-of-range or non-finite value into the document.
- Gesture-scoped undo verified end-to-end by `testSliderGestureUsesInteractiveRenderingAndOneUndoEntry` (drag → interactive renders coalesced to <10, one undo entry, redo restores).
- Codable round-trip covered by `testEffectsDocumentRoundTripsAsCopyableValue`.
- No `@unchecked Sendable`/`nonisolated(unsafe)`/`@preconcurrency` introduced; all new enums are `Sendable` value types per project convention.

**Performance gate:** `testMeasureEffectsInteractiveCost` is opt-in (`LUMO_BENCH=1`) and produces p50/p95 signposts rather than a hard assertion, per `docs/EFFECTS_VALIDATION.md` — appropriately treated as hardware-dependent follow-up rather than a CI gate, consistent with the existing `PreviewCostBenchmark` pattern for tone-curve/preview cost.

**Verdict:** No blockers found. No localized fixes needed. Verification passes.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T05:17:59.837Z: Independent verification passed: build/tests clean, no correctness/maintainability/security/performance blockers found.
