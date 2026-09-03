---
id: LUMO-101
title: Add crop functionality to the photo editor
type: task
status: done
priority: high
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-09-01T17:47:15.115Z
updated: 2026-09-01T19:25:01.226Z
order: zh
board: product
commits:
  - 33cba94
---

## Objective

Add a non-destructive crop workflow to the photo editor.

## Context

Crop is part of the intended editing model and is already reserved in the edit clipboard shape, but
there is no user-facing crop control or rendered crop stage. It should compose cleanly with RAW
development, adjustments, Look/LUT, effects, comparison, and export.

## Acceptance criteria

- [ ] The editor provides a discoverable crop tool with an interactive crop region, reset/cancel
  behavior, and a clear committed state.
- [ ] Crop is stored as a normalized, Codable, non-destructive edit and survives save/relaunch,
  undo/redo, and copy/paste according to the existing clipboard contract.
- [ ] Preview, side-by-side comparison, and full-resolution export render the same crop, preserving
  orientation and correct aspect/extent behavior.
- [ ] Crop interaction supports at least freeform framing within image bounds; any aspect-ratio,
  straighten, or rotation support is explicitly scoped and tested rather than implied.
- [ ] Add model, render-pipeline, interaction, persistence, undo, and preview/export parity tests.

## Implementation notes

Relevant code: `EditDocument`, `EditClipboard.CropCategory`, `RenderPipeline`, canvas/preview
interaction, and inspector views. Keep crop separate from transient zoom/pan state and make the
composition order explicit, especially for post-crop Effects such as vignette.

### Comment — codex @ 2026-09-01T19:13:35.424Z

Implemented in commit 61ed319. Added normalized Codable CropAdjustments with legacy defaults, non-destructive freeform crop overlay with corner handles and Apply/Reset/Cancel/Escape behavior, post-LUT/pre-vignette render composition, comparison-frame retention, persistence/undo/redo/copy-paste integration, and preview/export extent/pixel parity tests. Verification: swift test (557 passed, 26 expected skips); swift build -c release passed; git diff --check passed; dg validate passed.

### Comment — claude @ 2026-09-01T19:24:56.141Z

## Verification report (independent counterpoint review)

Scope: reviewed commit 61ed319 (crop model, render-pipeline composition, interaction, persistence/undo/clipboard, preview/export parity) against LUMO-101's acceptance criteria.

**Checks run:**
- `swift build` (debug) — clean, only pre-existing CI-kernel deprecation warnings unrelated to this change.
- `swift build -c release` — clean.
- `swift test --filter Crop` — 8/8 crop tests pass (model, pipeline extent/parity, interaction workflow incl. undo/redo and relaunch persistence).
- `swift test` (full suite) — all pass, 26 expected skips, no regressions.
- `git diff --check` — clean.
- `dg validate` — OK.

**Findings:**
1. (fixed, localized) `EditClipboardPayload.CropCategory.angle` was a dead field: declared, encoded/decoded, but never read anywhere and never connected to `EditDocument.CropAdjustments` (which has no angle concept). This implied rotation/straighten support in the clipboard contract that nothing in the render pipeline or UI actually implements — in tension with the acceptance criterion that non-freeform behavior be "explicitly scoped and tested rather than implied." Removed the field (commit 33cba94) and refreshed the now-stale "no crop stage yet" doc comment on `EditClipboardPayload`. Change is Codable-compatible with any already-persisted clipboard data (unknown JSON keys are ignored on decode). Re-ran the full test suite plus release build after the fix; all green.

**Design notes verified as correct, not bugs:**
- Crop composes post-LUT/pre-vignette as intended; `applyVignette`/`applyGrain` key off `image.extent` (midpoint/shortest-side), so they remain correct after crop shifts the extent — confirmed by the existing `testVignetteUsesPostCropAspectRatioAndPreservesHighlights` test and the new pixel-parity test.
- `CropAdjustments.normalizedRect` is in the *oriented* source coordinate space; `ImageDecoder.orientedLoadOptions` bakes EXIF orientation into the decoded `CIImage` before `sourceSize`/pipeline extents are derived, so the overlay, preview, and export all agree on the same space.
- `originalForComparison` deliberately retains `crop` (unlike light/color/effects) so comparison keeps a consistent frame — matches the "comparison-frame retention" behavior claimed in the implementation comment.
- Draft-vs-committed separation (`cropDraft` vs `document.crop`) keeps in-progress drags out of persistence/undo/export, matching the non-destructive requirement.

**Verdict: PASS.** No unresolved blockers. One localized cleanup applied and verified.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T19:25:01.225Z: Independent verification passed. Fixed one localized finding (dead angle field in EditClipboard.CropCategory implying unscoped rotation support); re-ran full test suite, release build, git diff --check, dg validate — all clean.
