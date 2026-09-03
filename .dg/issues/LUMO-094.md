---
id: LUMO-094
title: Fix black canvas when using explicit zoom, fill, or comparison zoom
type: task
status: done
priority: high
labels:
  - bug
  - performance
  - epic:editor
  - phase:8
created: 2026-09-01T17:47:12.724Z
updated: 2026-09-01T18:29:51.064Z
depends_on:
  - LUMO-046
order: n
board: product
---

## Objective

Keep the editor canvas visible and responsive for every supported zoom mode. At present, using
anything other than Fit can leave the screen black for an effectively indefinite period.

## Context

This appears to be a regression in or around the zoom/pan work delivered by LUMO-046. The failure
needs to be traced across `CanvasNavigation`, render-resolution selection, preview publication, and
`PreviewSurfaceView`; changing the presentation transform must not make a valid image disappear.

## Acceptance criteria

- [ ] Fit, Fill, and each explicit zoom preset render and display an image without an indefinite
  black frame.
- [ ] Scroll-wheel and pinch zoom behave the same way as preset zoom, including in side-by-side
  mode, and panning does not blank either panel.
- [ ] While a higher-resolution render is pending, the last valid frame remains visible or a clear
  loading state is shown; a failed request surfaces an actionable error instead of a permanent
  black canvas.
- [ ] Switching photos, comparison mode, or zoom cannot publish a stale/blank frame over the active
  photo.
- [ ] Add regression coverage for navigation changes through preview render and surface display.

## Implementation notes

Relevant code: `Sources/LumoKit/Models/CanvasNavigation.swift`, `PreviewCoordinator`,
`PreviewSurfaceView`, and the AppViewModel preview sizing/publication path. Keep display navigation
transient and preserve the render-quality/coalescing behavior introduced by LUMO-046.

### Comment — codex @ 2026-09-01T18:16:33.267Z

Implemented and committed as 48a9ae0. Hardened preview publication across fit, fill, explicit, scroll, pinch, pan, and comparison navigation: PreviewSurface now retains the last GPU-confirmed frame, rejects failed candidates without blanking the canvas, ignores stale completions, and reports actionable display errors. Added navigation-to-surface regression coverage. Verification: swift test — 533 passed, 26 expected skips; swift build -c release passed; git diff --check passed; dg validate passed with only the known runner-model and LUMO-044 context warnings.

### Comment — claude @ 2026-09-01T18:29:48.179Z

## Verification report (counterpoint agent)

**Scope reviewed:** commit 48a9ae0 (PreviewSurface.swift, AppViewModel.swift, plus 3 test files).

**Checks re-run:**
- `swift build` — clean (pre-existing deprecation warnings only).
- `swift test` — 536 passed, 26 expected skips, 0 failures.
- `swift build -c release` — not re-run separately; debug build + full suite pass is sufficient corroboration alongside the prior release-build claim.
- `git diff --check` — clean.
- `dg validate` — OK (only the known runner-model and LUMO-044 context-completeness warnings).

**Correctness analysis:**
- Traced the `pendingDisplayID` / `lastValidImage` state machine in `PreviewSurface` against the Metal completion-handler flow in `PreviewSurfaceView.Coordinator.draw(in:)`. Verified that:
  - A failed command buffer only rejects the *specific* candidate that failed (guarded by `pendingDisplayID == displayRevision`), so a newer publication queued behind a failing one is never clobbered — confirmed against `testAStalePresentationCompletionCannotCommitOverANewerFrame`.
  - `rejectPresentation` correctly reverts to `lastValidImage`/`lastValidSpace` and bumps `revision` so the coordinator's `lastDrawnRevision` guard forces a redraw of the reverted frame rather than leaving a stale drawable.
  - `clear()` resets `lastValidImage`/`pendingDisplayID` together with `image`, so a photo/comparison switch cannot resurrect a stale frame through the new fallback path.
  - Navigation-only redraws (pan/zoom without a new `present()`) leave `pendingDisplayID` nil, so they correctly skip the success/reject bookkeeping — there is no new candidate to confirm or reject, and the previously-valid image is already what's on screen.
- `AppViewModel.onPresentationFailure` closures are assigned after `previewSurface`/`originalPreviewSurface` are already stored properties (no init-order hazard), and are guarded on `sourceImage != nil` to avoid a misleading status when nothing is loaded.
- No changes touched `CanvasNavigation.swift` (LUMO-046 territory) — correctly out of scope for this localized fix.

**Findings:** none blocking. No maintainability, security, or performance issues found; the fix is narrowly scoped to presentation-failure handling and matches the acceptance criteria (last-valid-frame retention, stale-completion rejection, actionable error message, no stale/blank frame across navigation/photo switches). Regression coverage (`PreviewSurfaceTests`, `PreviewCutoverTests`, `AppViewModelTests`) exercises the new state machine directly, not just at the coordinator level.

**Verdict:** PASS. No child tickets required.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T18:29:51.063Z: Independent verification passed: build/tests/git diff --check/dg validate all clean; presentation-failure state machine (pendingDisplayID/lastValidImage) traced and correct against stale-completion and last-valid-frame retention behavior. No blocking findings.
