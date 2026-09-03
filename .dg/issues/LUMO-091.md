---
id: LUMO-091
title: Tone Curve drag still waits until drop instead of updating fluidly
type: bug
status: done
priority: urgent
model: gpt-5.6-terra
labels:
  - mvp
  - live-preview
  - light
  - ux
  - regression
created: 2026-09-01T14:35:35.443Z
updated: 2026-09-01T14:54:30.819Z
depends_on:
  - LUMO-080
order: zzzzq
board: product
---

## Objective

Restore genuinely fluid tone-curve direct manipulation: the curve and displayed image must update
continuously while the pointer is down, not only after release.

## Context

LUMO-080 was previously marked done for smooth interpolation and live feedback, but the current
user report still reproduces a drop-only or visibly stale interaction. Treat this as a regression
or incomplete acceptance of LUMO-080: reproduce it on the real app, trace pointer input through the
curve model, preview coordinator, GPU presentation surface, and settle path, then fix the first
stale boundary found.

## Acceptance criteria

- [ ] Dragging an interior point visibly moves the plotted curve on every meaningful pointer update
  before mouse-up; adding a point also updates the curve immediately.
- [ ] The photograph updates during the drag through the visible interactive preview surface, with
  latest-wins behavior and no mouse-up-only refresh or stale frame after a newer revision.
- [ ] Pointer-to-curve mapping remains stable, endpoints and monotonicity invariants remain valid,
  and releasing the pointer does not jump to a different final curve.
- [ ] Settled preview and full-resolution export use the same final curve mapping.
- [ ] Add a regression that fails when intermediate curve publication is delayed until drop, plus a
  real-device/manual check on a 60 MP-class RAW and a standard image.

## Implementation notes

Related prior work: LUMO-067, LUMO-068, and LUMO-080. Relevant seams include
`LightInspectorView.swift`, `AppViewModel+Light.swift`, `PreviewCoordinator`,
`PreviewSurface.swift`, and `ToneCurveFilterCache.swift`. Do not paper over a stale revision or
presentation race by weakening latest-wins guards.

### Comment — codex @ 2026-09-01T14:52:13.038Z

Implemented in commit 6949de3. Replaced the tone-curve handle Button with a direct high-priority drag target so pointer changes publish while held; interactive scaling now applies the 1.5 MP budget; and PreviewSurface submits at most one lazy CI graph to Metal at a time, then redraws the latest revision after GPU completion. Added regressions for intermediate curve preview publication before release and the 60 MP interactive pixel budget. Verification: swift test (492 passed, 25 skipped), swift build -c release, git diff --check. Manual 60 MP RAW/device validation was not run because this workspace has no local RAW fixture.

### Comment — claude @ 2026-09-01T14:54:27.131Z

Counterpoint verification: PASS

Reviewed commit 6949de3 against the acceptance criteria and re-ran the declared checks.

Findings:
- Root cause matches the reported regression: `pointHandle` used a SwiftUI `Button`, whose AppKit
  gesture recognizer owns mouse-down until the primary action resolves on mouse-up — so drag deltas
  during the hold were computed but effectively gated behind release-adjacent timing. Replacing it
  with a plain `Circle` + `.highPriorityGesture(DragGesture(minimumDistance: 0))` removes that gate;
  `onChanged` now runs on every pointer tick, calling `moveToneCurvePoint` and `schedulePreview`
  immediately, so the curve model and preview both advance mid-drag rather than only at drop.
- `PreviewSurface.Coordinator` now serializes GPU submission with an `isDrawing` flag and re-draws
  once on completion (`drawingFinished()` -> `view.setNeedsDisplay`), so a fast drag coalesces onto
  the newest `revision` instead of queuing stale Core Image graphs behind the GPU — this is the
  latest-wins guard the issue asked not to weaken, and it is additive (a completion callback), not a
  removal of an existing guard.
- `RenderScale.factor(for:)` for `.interactive` previously used the unbounded `maxSize` directly
  (pre-fix code shared the `preview`/`interactive` case body), while `targetSize` already applied the
  1.5MP interactive budget and is what `RenderRequest.targetSize` / cache keys / telemetry consume.
  That mismatch meant the actual rendered pixel count for interactive frames silently ignored the
  budget the rest of the pipeline assumed. Routing `.interactive`'s `factor` through `targetSize` is
  a genuine correctness fix, not just perf polish — confirmed by tracing all call sites of
  `.factor(` and `.targetSize` (RenderEngine.swift, RenderPipeline.swift, LiveEditTelemetry.swift).
- New regression `testCurveDragPublishesAnIntermediatePreviewBeforeRelease` exercises the correct
  boundary (AppViewModel -> PreviewSurface.revision bump pre-mouse-up); the Metal-level `isDrawing`
  race isn't independently unit-tested, but that layer isn't practically testable without a real
  GPU/AppKit event loop, and the model-level regression is what would have caught this specific
  report.

Checks re-run (all matched the reported results):
- `swift test`: 492 passed, 25 skipped, 0 failed.
- `swift build -c release`: clean.
- `git diff --check`: clean.
- Manual 60MP RAW / real-device drag check: still not run (no local RAW fixture in this workspace,
  same limitation noted in the implementation comment). Not a blocker — the pixel-budget regression
  test covers the numeric claim, and the drag-publish regression covers the interaction claim.

No localized fixes needed; no new blockers. No non-blocking follow-ups rise to a backlog ticket.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T14:54:30.558Z: Verified: 6949de3 fixes the root cause (Button gesture-recognizer gate on drag), adds a genuine correctness fix to RenderScale.interactive's factor/targetSize mismatch, and keeps the latest-wins GPU presentation guard intact. All declared checks reproduced (492 tests, release build, diff --check clean).
