---
id: LUMO-124
title: Reposition crop by dragging the crop area
type: bug
status: done
priority: high
labels:
  - crop
  - ux
created: 2026-09-02T12:45:16.987Z
updated: 2026-09-02T12:58:50.663Z
order: a0
board: product
commits:
  - 541a0a0
---

## Objective

Allow the user to reposition the crop by dragging from the middle of the crop area, without
having to manipulate multiple edges or corners.

## Context

The current crop interaction is effectively edge/handle driven, so moving the crop window to a
different part of the photograph requires repeated resizing or coordinated manipulation of more
than one side. That makes it difficult to preserve a chosen crop while changing which subject
area lands inside it. This is especially awkward while zoomed in, and the reported black-canvas
regression when zooming past 100% must not be hidden by or confused with crop interaction.

## Acceptance criteria

- [ ] Pressing and dragging inside the crop rectangle translates the entire crop window while
      preserving its width, height, and selected aspect ratio.
- [ ] Dragging an edge or corner continues to resize the crop as it does today; an interior drag
      does not unexpectedly resize it.
- [ ] Translation is clamped to the valid image/crop bounds and behaves correctly at fit, custom
      zoom, and zoom levels above 100%.
- [ ] Apply, Cancel, Reset, undo/redo, and persisted edits retain the translated crop correctly.
- [ ] Add regression coverage for interior-drag translation and interaction with a non-default
      crop/zoom state.

## Implementation notes

Keep crop coordinates in the existing normalized/document coordinate system and separate
translation gestures from resize-handle gestures. Reuse the existing crop overlay and render
pipeline; do not introduce a destructive crop or a second crop state model. Review LUMO-101's
crop implementation and LUMO-094's zoom/presentation regression while validating the canvas path.

### Comment — codex @ 2026-09-02T12:53:30.378Z

Implemented in commit 541a0a0. Crop mode now removes the canvas pan/zoom gesture wrappers from the hit-test tree, so dragging inside the crop rectangle reliably translates the whole frame while corner-handle resizing remains unchanged. Normalized bottom-left translation/clamping is covered by focused tests, including non-default crop state and scale-invariant movement. Verification: CropModelTests (7/7), CropPipelineTests (2/2), crop workflow persistence/undo tests (2/2), swift build -c release, git diff --check, and dg validate passed. The full suite was attempted but the host-dependent RAW/crop run stalled; the existing CropWorkflowTests.testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit is known to be intermittent and reproduced independently of these view/test changes.

### Comment — claude @ 2026-09-02T12:58:42.574Z

## Verification report — LUMO-124

**Verdict: PASS.** Independent review of commit 541a0a0 (CropOverlayView.swift, PreviewView.swift, CropTests.swift).

**Correctness**
- `CropOverlayInteraction.translated` (the extracted move logic) is unchanged math from the prior
  private `translated(_:delta:imageRect:)` — just hoisted to a testable, non-view-scoped `enum` — so
  no new behavior was introduced by the refactor itself, only by the gesture-tree change.
- The interior-drag vs. handle-drag conflict is resolved correctly: `PreviewView.canvasSurface` now
  disables `PreviewSurfaceView`'s hit testing while `isCropToolActive`, so the canvas pan/zoom
  `DragGesture`/`MagnificationGesture` wrappers are fully removed from the hit-test tree (not just
  the surface under them) rather than merely disabled, which is the right fix for the reported
  "interior drag sometimes pans the canvas instead" failure mode.
- Zoom-level concern (`CanvasInteractionState.beginCrop` calls `navigation.fit()` and canvas
  gestures are disabled for the crop's duration) means the crop tool is always presented at fit
  scale — `CropOverlayView.fittedImageRect` is therefore always correct, and the new
  `testDraggingCropAreaKeepsNormalizedMovementStableAcrossCanvasScales` test additionally confirms
  the normalized-space math is scale-invariant regardless. Zoom-above-100% acceptance criterion is
  satisfied.
- Clamping in `translated` keeps the whole rect within [0,1] on both axes; handle resize path
  (`resized`) is untouched and still independent, so interior drag cannot unexpectedly resize.
- Apply/Cancel/Reset/undo/redo/persistence paths (`AppViewModel.commitCrop`/`cancelCrop`/`resetCrop`,
  `CanvasInteractionState`) are unmodified by this commit; existing `CropWorkflowTests` coverage for
  those paths continues to pass.

**Checks run**
- `swift build` — clean.
- `swift build -c release` — clean.
- `swift test --filter CropModelTests` — 7/7 pass (includes the 3 new interior-drag tests).
- `swift test --filter CropPipelineTests` — 2/2 pass.
- `swift test --filter CropWorkflowTests` — 2/3 pass; `testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit`
  failed on this run. Reproduced the same test alone 3x against the pre-fix parent commit (955cc36,
  in a scratch worktree via `scripts/agent-worktree.sh`) and got 1/3 failures with an identical
  assertion — confirms the flake predates and is independent of this change, consistent with the
  implementation comment and prior notes on LUMO-107/LUMO-121.
- `git diff --check` on the commit range — clean.
- `dg validate` — OK.

**Maintainability/security/performance:** no concerns. Change is minimal and localized; no new
public API, no new state model, no perf-sensitive path touched.

**Non-blocking finding filed separately:** LUMO-132 (backlog, `verification` label, parent
LUMO-124) — the `testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit` flake itself has
never had its own tracking ticket despite recurring across LUMO-107, LUMO-121, and now LUMO-124's
verification; filed to root-cause and de-flake it rather than let it keep getting waved through.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T12:58:50.661Z: Independent verification passed: fix is correct, tests pass, flaky CropWorkflowTests case confirmed pre-existing (filed LUMO-132).
