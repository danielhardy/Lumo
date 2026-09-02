---
id: LUMO-134
title: Reconcile long-edge export plan with actual encoded pixel dimensions
type: task
status: backlog
priority: low
labels:
  - verification
created: 2026-09-02T16:43:09.373Z
updated: 2026-09-02T16:44:09.759Z
depends_on:
  - LUMO-051
order: zzy
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
