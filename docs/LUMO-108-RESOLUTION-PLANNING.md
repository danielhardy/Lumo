# LUMO-108 resolution planning record

The canvas now selects one of five source-detail levels (`1/8`, `1/4`, `1/2`, `3/4`, and native)
instead of using a continuously varying target box. The selected level is bounded by the existing
preview/developed-source LRU limits. A downgrade waits for 15% headroom below the next level;
upgrades happen as soon as the current level is inadequate.

The required source scale is computed from the committed normalized crop, the panel's actual
backing-pixel viewport, and the canvas fit/fill/zoom transform. Crop is still applied after the
adjustment graph, so spatial-filter ordering, crop alignment, grain phase, and vignette geometry
are unchanged. A crop that is 1/4 of the source in both dimensions therefore requests native
source detail whenever the viewport would otherwise enlarge that crop.

`MTKView.drawableSize` supplies the viewport. This avoids `NSScreen.main` assumptions for mixed-DPI
windows and makes each side-by-side panel size the input to planning. The planner also records the
visible source rectangle for future ROI profiling; pan remains presentation-only and does not
trigger source development.

## ROI/tile decision

This implementation intentionally does not add explicit tiles. The pipeline has crop, vignette, and
grain after the adjustment/LUT stages, and the existing completed-texture boundary makes warm pan,
fit, and zoom a presentation transform. Moving crop or materializing per-tile prefixes would change
the graph's spatial support and would make grain/vignette phase handling a new correctness surface.
Core Image remains responsible for ROI evaluation inside the graph. A tile path should be added only
after a Metal System Trace demonstrates that native-resolution visible traversal does more work than
Core Image's ROI already requires; the recorded `visibleSourceRect`, effective render dimensions,
cache statistics, and existing render/presentation telemetry are the measurement seams for that
follow-up.

## Deterministic verification

Generated planner fixtures use a 6000x4000 standard source, 1600x1200 and 800x1200 backing-pixel
viewports, a 1/4-by-1/4 crop, and zoom values 1x and 8x. The quarter-crop case selects 6000x4000;
uncropped fit selects 3000x2000; adjacent resize values stay on one level until hysteresis is
crossed. PreviewSurface coverage verifies that a 1/2-detail navigation candidate cannot replace a
valid native-detail frame for the same source/document.

The test suite exercises planner transitions and crop/export pixel parity. Hardware p95 warm/cold
navigation and native/RAW ROI work are not claimed from unit tests; capture them in Release on a
logged-in reference Mac using the existing performance matrix, recording source format/dimensions,
viewport/backing pixels, cache state, effective dimensions, and resident bytes.
