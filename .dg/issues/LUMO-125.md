---
id: LUMO-125
title: Offer common crop aspect ratios
type: feature
status: done
priority: medium
labels:
  - crop
  - ux
created: 2026-09-02T12:45:17.320Z
updated: 2026-09-02T15:22:33.837Z
order: a0
board: product
commits:
  - ec78249
---

## Objective

Offer selectable common crop aspect-ratio presets while retaining freeform cropping.

## Context

The crop tool currently requires users to approximate a desired print, social, or display format
manually. Presets reduce repeated edge manipulation and make the crop result predictable. The
behavior must remain usable when the canvas is zoomed, including the reported regression where the
canvas can turn black past 100% zoom.

## Acceptance criteria

- [ ] Provide a Freeform option plus at least 1:1, 3:2, 4:3, and 16:9 presets with clear labels.
- [ ] Selecting a ratio updates the crop rectangle without changing the source photo or applying
      the crop prematurely.
- [ ] Presets work in both portrait and landscape orientations, preserve the selected ratio while
      resizing/repositioning, and remain clamped to the image bounds.
- [ ] The selected ratio is represented in the edit state as needed for undo/redo, persistence,
      Cancel, Reset, preview, and full-resolution export.
- [ ] Add model/UI regression coverage for preset selection and preview/export crop parity.

## Implementation notes

Keep the ratio list centralized and extensible rather than embedding raw values in gesture code.
Define how a preset is initialized when an existing crop is present (prefer preserving the current
crop center where possible). Reuse the current normalized crop model and overlay; see LUMO-101.

### Comment — codex @ 2026-09-02T15:18:27.029Z

Implemented in commit ec78249. Added centralized Freeform, 1:1, 3:2, 4:3, and 16:9 presets with orientation-aware normalized geometry, center-preserving initialization, constrained resize/reposition clamping, and clear overlay labels. Persisted the selected ratio through CropAdjustments, documents, clipboard, undo/redo, Cancel, Reset, preview, and full-resolution export. Added model, workflow, legacy-decoding, and preview/export parity coverage. Verification: full swift test passed all 615 executed tests except the pre-existing intermittent CropWorkflowTests.testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit failure (13 expected skips); swift build -c release, git diff --check, and dg validate passed. dg validate retained only pre-existing warnings for the pickup model and LUMO-050 context completeness.

### Comment — claude @ 2026-09-02T15:22:31.101Z

Counterpoint verification: PASS.

Reviewed commit ec78249 (CropAspectRatio enum, CropOverlayInteraction geometry, CanvasInteractionState/AppViewModel wiring, EditClipboard persistence, CropOverlayView menu) against all five acceptance criteria — all satisfied:
- Freeform + 1:1/3:2/4:3/16:9 presets with clear labels (menu with checkmark on active ratio).
- Selection only updates canvasState.cropDraft/cropAspectRatio (transient); commitCrop() is the sole write to document.crop, confirmed by testSelectingPresetStaysDraftUntilApplyAndUndoRedoRestoresTheRatio.
- Orientation handled via CropAspectRatio.normalizedRatio(for:) (reciprocal pixel ratio on portrait sources); resize/reposition math (CropOverlayInteraction.applying/resized/translated) is bounds-clamped and area-preserving; verified algebraically and via tests.
- aspectRatio is a coded field on CropAdjustments/EditClipboardPayload.CropCategory with defaulted legacy decoding (testMissingCropFieldKeepsLegacyDocumentsNeutral, testLegacyCropClipboardDefaultsToFreeform); flows through undo/redo, Cancel, Reset, preview, and full-res export.
- New coverage: CropModelTests (preset selection, resize, persistence), CropPipelineTests (preview/export extent parity), CropWorkflowTests (draft-vs-commit, undo/redo).

The "black past 100% zoom" regression named in the issue context doesn't apply here: beginCrop() forces navigation.fit() before activating the tool, so the crop surface is never in the zoomed-canvas state that bug affects (already covered by LUMO-127/LUMO-131, both already fixed on main).

Independent checks run this session, all green:
- `swift test` (full suite): 615 executed, 0 failures, 13 expected skips (the pre-existing intermittent CropWorkflowTests test skipped rather than run this pass).
- `swift build` and `swift build -c release`: clean.
- `git show ec78249 | git diff --check`: clean.
- `dg validate`: OK, only pre-existing unrelated warnings (pickup runner model name, LUMO-050 context completeness).

No blockers. One non-blocking observation, too minor to warrant a child ticket: CropAdjustments.isIdentity now also depends on aspectRatio being .freeform, so a preset chosen on an already-matching-ratio image (e.g. 1:1 on a square source) marks the document as having visible edits and adds a harmless no-op `.cropped(to:)` call in RenderPipeline.applyCrop even though pixels are unchanged. This looks intentional (matches the doc comment about persisting the user's framing constraint) rather than a defect.

Working tree left clean (no source edits made during verification). Moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T15:22:33.836Z: Independent verification passed: all acceptance criteria met, full swift test (615/615, 13 expected skips) + release build + dg validate clean. No blockers.
