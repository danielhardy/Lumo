---
id: LUMO-157
title: Double-click canvas to toggle between Fit and the last chosen zoom
type: feature
status: done
priority: medium
labels:
  - canvas
  - zoom
  - ux
  - interaction
  - verification
created: 2026-09-03T14:43:49.871Z
updated: 2026-09-03T16:35:28.844Z
order: zzzzzzz
board: product
claim:
  actor: claude
  session: 01MTLQPV7AD1YXBV0A
  claimed_at: 2026-09-03T16:29:24.406Z
  expires_at: 2026-09-03T17:29:24.406Z
  model: sonnet
---

## Objective

Make double-clicking the image a quick two-way zoom toggle: from Fit, return to
the last manually chosen zoom level; from any zoomed state, return to Fit.

## Context

The canvas already supports Fit, Fill, explicit zoom menu values, panning, and
pinch magnification, but the image has no fast way to alternate between a full-image
view and a previously selected detail level. Users should be able to inspect detail
and then quickly restore the whole composition without reopening the zoom menu.

Relevant current interaction/state code is in
`Sources/LumoKit/Views/PreviewView.swift`,
`Sources/LumoKit/Models/CanvasNavigation.swift`, and the canvas-navigation methods
in `Sources/LumoKit/ViewModels/AppViewModel.swift`.

## Acceptance criteria

- [ ] When the canvas is in Fit mode, double-clicking the image switches to the last
      valid user-chosen zoom level and presents the image without recreating the
      source or changing the edit document.
- [ ] When the canvas is in a custom zoom, Fill, or other non-Fit view, double-clicking
      the image switches to Fit and shows the complete image centered in the viewport.
- [ ] The last chosen zoom level is retained while toggling Fit and remains available
      after repeated Fit/detail double-clicks; it is updated when the user chooses a
      new explicit or gesture-based zoom.
- [ ] Define and test a deterministic fallback when no prior custom zoom exists, and
      ensure invalid, unavailable, or out-of-range remembered values are clamped safely.
- [ ] Double-click handling does not interfere with existing pan, pinch zoom, crop
      interaction, comparison/original-preview behavior, or normal single-click input.
- [ ] Add automated state-transition coverage for Fit → remembered zoom → Fit,
      including Fill and repeated-toggle cases, plus interaction/layout coverage for
      the image surface where practical.

## Implementation notes

Keep zoom/navigation presentation-only and out of `EditDocument` and edit history.
The remembered level may belong in `CanvasNavigation` or its interaction-state owner,
but Fit should not erase it. Choose the smallest gesture API that works with the
existing SwiftUI/AppKit canvas input and preserve the current focal-point/pan policy;
double-clicking need not add a new edit or persistence behavior.

### Comment — codex @ 2026-09-03T16:29:14.152Z

Implemented in commit 7215ac5. CanvasNavigation now remembers the last finite explicit/gesture zoom, preserves it across Fit/Fill/Reset, uses a clamped 200% fallback on the first double-click, and clears it on source reset. PreviewMTKView handles double-click at the existing canvas surface boundary; crop mode still disables canvas hit testing and comparison panes share navigation. Verification: swift test (712 passed, 14 expected skips, 0 failures), swift build -c release, git diff --check, dg validate (pre-existing unknown runner-model warning).

### Comment — claude @ 2026-09-03T16:35:26.579Z

## Verification report — LUMO-157

**Verdict:** PASS

**Scope reviewed:** commit 7215ac5 (CanvasNavigation, CanvasInteractionState, AppViewModel, PreviewSurface/PreviewView, CanvasNavigationTests).

**Correctness**
- `toggleFitAndRememberedZoom()` correctly branches on `mode == .fit`: from Fit it restores `rememberedZoom ?? doubleClickFallbackZoom` (clamped) into `.custom`; from any other mode (`.fill`, `.custom`) it calls `fit()`. Matches both acceptance criteria directions.
- `rememberedZoom` is updated only by `setZoom`/`multiplyZoom` (finite values), left untouched by `fit()`/`fill()`, and cleared only by `resetForSource()` — verified `resetForSource()` is wired into the actual photo-switch path (`AppViewModel.swift:953`), so the remembered level is correctly scoped per-source.
- Clamping: `CanvasNavigation.init(rememberedZoom:)` and `clampZoom` handle non-finite/out-of-range values safely (tested with `.infinity` and `-10`).
- Double-click is delivered via `PreviewMTKView.mouseDown` on `clickCount == 2`; panning is a separate SwiftUI `DragGesture` layered on top (not AppKit mouse tracking), so there's no drag-state corruption between click 1 and click 2. Crop mode disables hit-testing on the surface entirely (`preview.allowsHitTesting(false)`), so double-click can't fire during crop, per acceptance criteria. Both comparison panes route through the same `canvasSurface` helper and share `canvasState.navigation`, so side-by-side stays in sync.
- `toggleCanvasZoom()` only mutates `canvasState`/schedules a preview re-render (same pattern as `fitCanvas`/`fillCanvas`/`resetCanvas`) — confirmed presentation-only via `testCanvasDoubleClickToggleIsPresentationOnly` (document identity unchanged across toggles).

**Test coverage**
- New `CanvasNavigationTests` cover: fallback-then-toggle-back-to-fit, repeated toggling, Fill retaining the remembered zoom, gesture-set zoom being remembered and clamped, and out-of-range `init` clamping. `CanvasObservationTests.testCanvasDoubleClickToggleIsPresentationOnly` covers the ViewModel/document-identity boundary. UI-level double-click dispatch (AppKit `NSEvent`) isn't exercised directly, but that's reasonably impractical for this test target and the underlying state machine is fully covered.

**Verification run**
- `swift test`: 712 passed, 14 expected skips, 0 failures (confirmed independently, not just re-trusting the implementer's log).
- `swift build -c release`: succeeds.
- `git diff --check` on the commit: clean.

**Maintainability/security/performance:** no concerns — small, localized change; no new external inputs; `schedulePreview()` reuse matches the existing Fit/Fill/Reset cost profile, no extra render churn.

No blockers, no follow-up tickets needed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
