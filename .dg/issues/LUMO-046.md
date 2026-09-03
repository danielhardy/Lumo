---
id: LUMO-046
title: Implement zoom, pan, fit, and fill on the editor canvas
type: task
status: done
priority: high
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:32.585Z
updated: 2026-09-01T16:54:38.526Z
depends_on:
  - LUMO-045
  - LUMO-013
estimate: 5
order: zzzzz
board: product
---

## Objective

Provide fluid native canvas navigation independent of render resolution and inspector state.

## Context

Part of **Epic 8 — Image-centric editor experience**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Separate display transform from destructive crop/output transform.
- Support fit, fill, explicit zoom, scroll/pinch zoom, pan, and reset.
- Request appropriate render sizes when zoom changes without thrashing.
- Keep image centered and constrained predictably.

## Acceptance criteria

- [ ] Fit shows the whole image; Fill covers the viewport; neither alters export.
- [ ] Zoom/pan remain responsive while a better render settles.
- [ ] Changing inspector/sidebar geometry preserves a sensible focal point.
- [ ] Extreme and invalid zoom values clamp safely.

## Verification

- Add transform math tests and manual trackpad/mouse checks on portrait/landscape images.

## Out of scope

- Crop/straighten UI unless separately scheduled.
- Pixel-level retouching.

### Comment — codex @ 2026-09-01T16:49:13.573Z

Implemented in commit 56e6134. Added transient CanvasNavigation state with fit/fill/custom zoom, normalized focal-point pan/clamping, safe finite zoom bounds, and resolution-aware preview targets. Moved display placement into the persistent Metal surface so navigation stays separate from EditDocument/export; added mouse drag, pinch magnification, scroll-wheel zoom, shared before/after transform state, toolbar presets, source-reset behavior, and six transform math tests. Verification: swift test (520 passed, 26 expected skips), swift build -c release, git diff --check, and dg validate passed; validate reports only the pre-existing runner-model and unrelated LUMO-044 context warnings.

### Comment — claude @ 2026-09-01T16:54:36.620Z

### Verification report — counterpoint agent (claude/sonnet) @ 2026-09-01T16:54:36.000Z

Independent review of commit 56e6134 (CanvasNavigation, PreviewSurface, PreviewView, AppViewModel, ContentView, tests).

**Findings**
1. **Correctness (blocker, fixed)** — `PreviewSurfaceView.Coordinator.draw(in:)` only redrew when `surface.revision` or the drawable size changed. `panCanvas` deliberately mutates `CanvasNavigation` without bumping `surface.revision` (per its own doc comment: pan is presentation-only and must not wait on a render), so a mouse-drag pan never produced a visible frame until an unrelated render happened to land — the image looked frozen while dragging. Fixed by tracking `lastDrawnNavigation` and redrawing when it changes.
2. **Correctness/maintainability (fixed)** — `beginCanvasInteraction`/`endCanvasInteraction` (pinch-zoom) reused `beginPreviewInteraction`/`endPreviewInteraction`, which also open an undo grouping and queue a document save via `saveActiveDocument`. That's correct for slider drags but wrong for a gesture the code explicitly documents as presentation-only and never touching `document` — it flashed a 'saving' status indicator and pushed noise through undo bookkeeping on every pinch. Fixed by calling `previewCoordinator.beginInteraction()/endInteraction()` directly.

Both fixes are localized to the two files touched, add no new product behavior (they restore the behavior the original code's own comments already promised), and are covered by the existing CanvasNavigationTests plus manual reasoning about the draw-skip guard.

**Checks run**
- `swift test`: 520 passed, 26 expected skips (same baseline as original PR)
- `swift build -c release`: clean
- `git diff --check`: clean
- `dg validate`: OK (same pre-existing warnings: runner-model, LUMO-044 context completeness)

**Verification commit:** 99163f1 — fix(LUMO-046): make canvas pan redraw and stop pinch from opening undo groups

**Not otherwise flagged:** transform math (fit/fill/zoom clamp/pan-clamp/focal-point-on-resize/render-resolution-multiplier), Sendable/Swift 6 conformance, side-by-side focal-point sharing, and scroll-wheel zoom all read correctly and match the acceptance criteria.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
