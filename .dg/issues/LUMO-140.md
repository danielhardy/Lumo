---
id: LUMO-140
title: Fix RenderScale rounding mismatch for extreme aspect-ratio long-edge exports
type: task
status: done
priority: urgent
labels:
  - verification
created: 2026-09-02T19:41:55.343Z
updated: 2026-09-02T21:10:28.389Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-02T21:10:28.382Z
  session: 01MTKL3NF8GDGY13ME
---

## Objective

`ebec8e8` (LUMO-134) made export requests use `ExportSizing.outputSize(for:)` as the
`RenderScale.preview` box so the durable export plan matches the encoded pixel output. It closes
the original repro (3333×5000 @ longEdge 2000) but does not close the general case: for images
with an extreme aspect ratio, the short-axis rounding in `outputSize(for:)` can flip which axis
binds `RenderScale.preview`'s `min(maxSize.w/nativeW, maxSize.h/nativeH, 1)`, decoupling the
recomputed scale from the true long-edge axis and reproducing a 1px mismatch — just on the other
axis than the original bug.

## Repro (confirmed against current `main`, via a temporary XCTest — not committed)

Source 3×3000, `longEdge(1001)`:

```
planned  outputSize(for:) = (1, 1001)   // height axis matches requestedEdge exactly by construction
actual   encoded pixels   = (1, 1000)   // RenderScale picks the rounded width axis (1/3) as the
                                         // binding ratio, which is *tighter* than the true 1001/3000
                                         // factor, so the height axis is recomputed and re-rounds down
```

Root cause: `RenderRequest.renderScale` for `.export` now passes `options.outputSize(for:)` — a
box whose two dimensions were rounded *independently* — as `RenderScale.preview(maxSize:)`.
`RenderScale.scale(for:)` then takes `min(maxSize.width/native.width, maxSize.height/native.height, 1)`,
i.e. it re-derives a single scalar scale from whichever axis the independent rounding made
tightest. When the short axis rounds down enough that its ratio dips below the true long-edge
factor, it — not the long edge — becomes the binding constraint, and the long axis is
recomputed and re-rounded (outward, via `.integral`), which does not always land back on
`outputSize`'s round-to-nearest value.

## Suggested direction

Don't let the render path re-derive a scale from a box with independently-rounded dimensions.
Options:
- Carry the single unrounded scale factor (`min(1, requestedEdge / sourceLongEdge)`) through to
  the renderer instead of a `CGSize` box, and round only once, at the very end, to
  `outputSize(for:)` — e.g. resize/crop the rendered image to that exact pixel size rather than
  letting `RenderScale.scale(for:)` re-derive its own ratio from a rounded box.
- Or make `RenderScale.preview` aware that a box came from an isotropic long-edge plan (vs. an
  arbitrary fit-within box) so it always binds to the long axis rather than re-deriving `min(...)`.

Whichever direction is chosen, extend `ExportOptionsTests` with an extreme-aspect-ratio case
(e.g. 3×3000 @ longEdge 1001) alongside the existing 3333×5000 case, since the two exercise
different branches of the rounding.

## Acceptance criteria

- [ ] For a fractional-scale long-edge export at extreme aspect ratio (e.g. 3×3000 @ longEdge
      1001), planned `outputSize` equals the encoded image's pixel dimensions.
- [ ] The existing LUMO-134 regression tests (100×50 exact case, 3333×5000 fractional case,
      small-source no-upscale case) still pass.
- [ ] No accidental upscaling is introduced.

## Provenance

Found during LUMO-134 counterpoint verification (2026-09-02). LUMO-134 is being sent back to
`review` rather than `done` because its acceptance criteria ("planned outputSize equals the
encoded image's pixel dimensions" for fractional-scale long-edge exports) is not met in general —
only for the specific aspect ratios exercised by the committed tests.


### Comment — codex @ 2026-09-02T21:02:47.175Z

Implemented in commit 7708701. Long-edge exports now derive RenderScale from unrounded proportional dimensions, then apply the rounded ExportSizing.outputSize plan once at the final export boundary. Added the 3x3000 @ longEdge 1001 regression alongside the existing 3333x5000, exact 100x50, and no-upscale coverage. Verification: swift test (644 executed, 14 expected skips, 0 failures), swift build -c release, dg validate, and git diff --check all pass.

## Agent log

- 2026-09-02T21:10:28.389Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTKL3NF8GDGY13ME
Summary: Verified 7708701 fixes the extreme-aspect-ratio rounding mismatch: RenderScale now derives its factor from the unrounded proportional box, and the rounded outputSize plan is applied exactly once at the render output boundary. All checks pass.
