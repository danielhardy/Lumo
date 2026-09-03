---
id: LUMO-134
title: Reconcile long-edge export plan with actual encoded pixel dimensions
type: task
status: review
priority: low
labels:
  - verification
created: 2026-09-02T16:43:09.373Z
updated: 2026-09-02T19:44:36.881Z
depends_on:
  - LUMO-051
  - LUMO-140
order: n
board: product
---

## Objective

Make `ExportSizing.outputSize(for:)` and the render engine's actual encoded output agree to the pixel, so the durable export plan never promises a dimension the encoder does not deliver.

## Context

Found during LUMO-051 counterpoint verification (non-blocking; commit e620439).

The two sizing paths use different rounding:

- **Planning** — `ExportSizing.outputSize(for:)` (`Sources/LumoKit/Models/ExportOptions.swift`) rounds each dimension `.toNearestOrAwayFromZero`.
- **Execution** — the engine maps long-edge sizing to `RenderScale.preview(edge × edge)` via `RenderRequest.renderTargetBox`, computes an unrounded scale factor, and then takes `image.extent.integral` (`Sources/LumoKit/Models/RenderEngine.swift`), which rounds the extent *outward*.

At fractional scale factors the plan and the encoded pixels diverge by 1px. Reproduced against a 3333×5000 source with `longEdge(2000)`:

```
PLANNED: (1333.0, 2000.0)     // 3333 × 0.4 = 1333.2 → rounds to 1333
ACTUAL pixels: 1334 2000      // extent 1333.2 → integral rounds to 1334
```

The engine test in `ExportOptionsTests` only covers the exact 100×50 → 40×20 case, where no rounding occurs, so the drift is untested. A Step 12 export UI that reports the planned size would show a dimension the file does not have.

## Acceptance criteria

- [ ] For a fractional-scale long-edge export (e.g. 3333×5000 @ longEdge 2000), planned `outputSize` equals the encoded image's pixel dimensions.
- [ ] The existing exact-case test (100×50 @ longEdge 40) still passes.
- [ ] No accidental upscaling is introduced by the reconciliation (source smaller than the long edge must stay full size).

## Implementation notes

Options: round the engine's effective scale to produce the planned extent exactly (preferred — the plan is the durable contract), or switch planning to outward rounding to mirror `integral`. Prefer fixing the engine path so `outputSize(for:)` stays the single source of truth; add the fractional repro above as a regression test.

### Comment — codex @ 2026-09-02T19:39:24.326Z

Implemented in commit ebec8e8. Export requests now use ExportSizing.outputSize(for:) as the RenderScale box, so outward extent integral agrees with the durable pixel plan without upscaling smaller sources. Added fractional 3333x5000 → 1333x2000 encoded-pixel regression coverage, retained the exact 100x50 case, and added a small-source no-upscale test. Verification: swift test (639 passed, 14 expected skips), swift build -c release, git diff --check, and dg validate passed; dg validate has only the existing pickup-model and unrelated LUMO-138 context warnings.

### Comment — claude @ 2026-09-02T19:42:24.276Z

Counterpoint verification: FAIL (sent back to review).

commit ebec8e8's fix (`RenderRequest.renderScale` now uses `options.outputSize(for:)` as the
`RenderScale.preview` box) closes the originally-reported repro (3333×5000 @ longEdge 2000,
confirmed still passing: `swift test --filter ExportOptionsTests` → 9/9 pass) but does not hold
in general, contrary to acceptance criterion 1 ("For a fractional-scale long-edge export ...
planned outputSize equals the encoded image's pixel dimensions").

Counterexample confirmed with a temporary XCTest against current `main` (not committed — reverted
after the run): source 3×3000, `.longEdge(1001)` →
  planned outputSize(for:)  = (1, 1001)
  actual encoded pixels     = (1, 1000)

Cause: `outputSize(for:)` rounds each axis independently. Feeding that rounded box back into
`RenderScale.preview(maxSize:)` lets `RenderScale.scale(for:)`'s `min(w-ratio, h-ratio, 1)`
re-derive a scalar from whichever axis rounding made tighter — for extreme aspect ratios that can
be the short axis instead of the long axis the plan was built from, so the long axis gets
recomputed and re-rounded independently of the original plan.

Filed LUMO-140 (urgent, depends_on'd by this issue) with the full repro and two candidate fix
directions. Verification commands run: `swift test --filter ExportOptionsTests` (full pass, 9/9),
plus the ad hoc counterexample test (reverted, not part of the tree — `git status --porcelain`
confirmed clean before and after).

Moving back to `review`; claim released.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
