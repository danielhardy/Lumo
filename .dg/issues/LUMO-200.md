---
id: LUMO-200
title: Auto Light engine (pure function, composable evaluators)
type: feature
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:55.845Z
updated: 2026-09-04T14:34:44.637Z
depends_on:
  - LUMO-199
order: zzzzzzh
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/AutoLightEngine.swift` +
`Sources/LumoKit/ViewModels/AppViewModel.swift` (`runAutoAdjustment`)
**Depends on:** LUMO-199
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §2, original proposal §30–36

## 1. Problem

Today's Auto (`AutoAdjustmentAnalyzer.analyze(histogram:)` in
`Sources/LumoKit/Models/AutoAdjustment.swift`) sets Light/Color from a global histogram alone. This
ticket adds a second, subject-aware path — `AutoLightEngine` — consuming `PhotoAnalysis`
(LUMO-194/197/198/199). **Auto is the first, but not the only, consumer of the mask foundation** —
this ticket must consume masks the same way the Masking UI (LUMO-201) will, through the shared
`SemanticMaskProviding`/`ToneAnalyzer` seam, at `.analysis` quality:

```swift
let subjectMask = maskService.mask(for: .subject, image: image, quality: .analysis)
let stats = toneAnalyzer.statistics(image: image, through: subjectMask)
```

Auto never gets a private/cheaper mask representation — it just requests the cheapest *quality*
level (`.analysis`), which the shared foundation already supports by design (LUMO-184).

## 2. Requirement (acceptance criteria)

1. `AutoLightEngine` is a **pure function**: `(analysis: PhotoAnalysis, currentEdits:
   EditDocument, configuration: AutoLightConfiguration) -> AutoAdjustmentResult`. No Vision, no
   Core Image, no actor, no async, no filesystem, no UI — matches `docs/PHASE3_SPEC.md` §2 and
   mirrors `RenderPipeline.buildImage`'s pure-function shape.
2. Composed from independent evaluators (`ExposureEvaluator`, `HighlightEvaluator`,
   `ShadowEvaluator`, `WhitePointEvaluator`, `BlackPointEvaluator`, `ContrastEvaluator`), each
   producing an `AdjustmentProposal { preferred, minimum, maximum, confidence }`, reconciled into
   concrete edit values.
3. Continuous response curves, not hard thresholds.
4. Hard safety bounds per parameter — document chosen bounds against Lumo's actual
   `AdjustmentNode`/Light value ranges.
5. `AutoAdjustmentResult` carries a structured `rationale: AutoRationale` per parameter.
6. Preserves artistic intent per `SceneCharacteristics` (LUMO-199): high-key stays high-key,
   low-key stays low-key, backlit protects background while opening subject shadows, an already-
   good image produces near-zero adjustments.
7. Versioned algorithm output, mirroring `AutoAdjustmentSettings.currentVersion`'s pattern.
8. **Integration**: `AppViewModel.runAutoAdjustment()` gains a path that, when `PhotoAnalysis` is
   available (from LUMO-195's coordinator, `.standard` level or better) and
   `quality.overallConfidence` clears a documented floor, uses `AutoLightEngine` instead of
   `AutoAdjustmentAnalyzer`. When analysis is unavailable/low-confidence, `runAutoAdjustment()`
   **must** keep working exactly as today via `AutoAdjustmentAnalyzer` — no regression.
9. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Do not delete or rewrite `AutoAdjustmentAnalyzer` — it stays the Tier-0 fallback; its existing
  tests must keep passing unmodified.
- Read `AppViewModel.swift:861-913` carefully before touching it — match its cancel-on-supersede
  and revision-guard-after-await discipline.
- Reconciling multiple evaluators' `AdjustmentProposal`s: a reasonable starting point is clamping
  each preferred value to the intersection of all applicable min/max ranges, preferring the more
  conservative bound if the intersection is empty. Document whatever you choose.
- **Do not build a second mask-consumption path for Auto.** If you find yourself writing code that
  reads mask pixels directly instead of calling `MaskedToneAnalyzer.statistics(image:through:)`
  (LUMO-193), stop — that's the bug this whole restructure exists to prevent.

## 4. Where to look

- `Sources/LumoKit/Models/AutoAdjustment.swift` — existing Tier-0 Auto to preserve as fallback.
- `Sources/LumoKit/ViewModels/AppViewModel.swift:842-913`.
- LUMO-193's `MaskedToneAnalyzer`, LUMO-184's `SemanticMaskProviding` — the only sanctioned way to
  get mask-restricted statistics.
- `Sources/LumoKit/Models/AdjustmentNode.swift`, `EditDocument.swift` — actual value ranges.

## 5. Testing

- `Tests/LumoKitTests/AutoLightEngineTests.swift` (new): unit test each evaluator in isolation;
  reconciliation step with conflicting proposals; golden-range tests per scenario (backlit, high-
  key, low-key, already-good, normal daylight) asserting ranges, not exact values.
- `Tests/LumoKitTests/AutoAdjustmentIntegrationTests.swift` (extend/add): assert
  `runAutoAdjustment()` still produces the existing Tier-0 result when `PhotoAnalysis` is
  unavailable/low-confidence — a hard regression test for the fallback contract.
- Full `swift test` stays green.
