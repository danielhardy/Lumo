---
id: LUMO-127
title: Prevent Clarity from corrupting large images at extreme values
type: bug
status: done
priority: high
labels:
  - effects
  - rendering
  - correctness
created: 2026-09-02T12:45:17.975Z
updated: 2026-09-02T13:24:08.613Z
order: zzx
board: product
commits:
  - 0d6a397
---

## Objective

Make Clarity safe across its full supported slider range, especially for large source photos.

## Context

Clarity shows a similar severe failure to Dehaze: at extreme settings the image can flip or squeeze
into a collapsed-looking result. The report specifically notes that the problem is more apparent
with larger photos, so small fixtures alone could miss the defect. This adjustment must change
local contrast/detail, not the image's geometry, orientation, or usable extent. Validate the result
also at zoom levels above 100% so the known black-canvas regression is not mistaken for a Clarity
failure.

## Acceptance criteria

- [ ] Clarity values across the full UI range preserve orientation, extent, aspect, and spatial
      placement; no flip, squeeze, collapse, or invalid geometry occurs.
- [ ] Regression coverage includes a representative large image, both slider directions, zero,
      maximum values, and the interactive-to-settled render transition.
- [ ] Preview, comparison, and full-resolution export remain finite and visually consistent for
      the same Clarity setting.
- [ ] Add a test that distinguishes a valid high-Clarity image from an extent/transform corruption,
      not merely a successful render completion.

## Implementation notes

Inspect the spatial-filter radius/scale, working-image extent, and any coordinate transforms used
by the Clarity stage. Ensure parameters are normalized for large images and that intermediate
images are finite and correctly bounded. Preserve the existing pipeline ordering and preview/export
parity rather than adding a special-case UI cap without diagnosing the render defect.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T13:24:08.607Z: Implemented bounded Clarity rendering with finite-value sanitization, exact input-extent clipping for spatial and mask intermediates, cache version 18, and large-raster full-range regressions covering orientation, geometry, interactive/settled preview, and export parity. Verification: swift test (602 passed, 13 expected skips), swift build -c release, git diff --check, dg validate OK with the existing pickup-model warning.
