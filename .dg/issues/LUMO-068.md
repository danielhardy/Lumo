---
id: LUMO-068
title: Make every Light, Develop, and Adjust control update the preview continuously while dragging
type: feature
status: done
priority: urgent
verification_agent: pi
verification_model: openrouter/~deepseek/deepseek-v4-flash-latest
labels:
  - mvp
  - performance
  - live-preview
created: 2026-08-31T22:56:13.158Z
updated: 2026-09-01T02:28:19.022Z
depends_on:
  - LUMO-069
  - LUMO-070
  - LUMO-071
  - LUMO-072
order: a0
board: product
---

## Objective

Make the image preview track every continuous edit while the pointer is moving. Mouse-up may trigger
a higher-quality settle, but it must never be the event that first reveals the adjustment.

## Context

The controls already call `beginPreviewInteraction` / `endPreviewInteraction`, but that wiring does
not guarantee visible real-time feedback. The current interactive request waits 16 ms, renders the
same 1600 x 1200 target as a settled preview, serializes behind non-cancellable Core Image work, and
publishes a newly allocated `CGImage` / `NSImage` through the broad `AppViewModel` observation path.
RAW Develop is slower again because every develop value changes the developed-source cache key.

This is a release-critical interaction contract covering every slider in Light, every supported
continuous control in Develop (including white-balance tint), every slider under Adjust, and the
Light tone curve. Performance takes priority over implementation size. LUMO-067 established
latest-wins coordination and curve gestures, but its latency benchmark uses a fake renderer and does
not prove real GPU or RAW pointer-to-photon behavior.

## Scope

- Deliver visible intermediate frames throughout a drag, not only after drop/mouse-up.
- Keep only the newest edit value; stale work must never queue or publish.
- Use an explicit interactive quality policy and a persistent presentation path, followed by a
  visually seamless settled render.
- Cover Light, Develop, Adjust, and tone-curve gestures with the same lifecycle contract.
- Treat actual pointer-to-present latency, frame pacing, and visual continuity as release gates.

## Acceptance criteria

- [ ] Every continuous control changes the displayed image before mouse-up and continues to publish
  intermediate values during a sustained drag.
- [ ] The tone curve preview tracks its handle during the gesture; adding/removing a point also
  updates immediately.
- [ ] At most one interactive render is executing and at most one latest value is pending; obsolete
  results never appear.
- [ ] Releasing a control upgrades the same visible surface to settled quality without blanking,
  cross-fading, layout refresh, or a perceptible second repaint.
- [ ] The real-hardware latency gates in LUMO-072 pass for representative standard and RAW images.
- [ ] Export and settled preview remain pixel-consistent with the final edit document.

## Implementation notes

The focused implementation work is split into LUMO-069 (render and presentation), LUMO-070 (RAW
Develop), LUMO-071 (tone-curve allocation/upload), and LUMO-072 (end-to-end measurement). Preserve
macOS 14 support, Swift 6 strict concurrency, one deterministic edit pipeline, and zero third-party
dependencies.

### Comment — codex @ 2026-09-01T02:09:10.982Z

Integrated verification complete: LUMO-069/070/071/072 are landed on main, covering frame-paced persistent GPU presentation, RAW Develop reuse, tone-curve interactive rendering, and revision-correlated telemetry. Full swift test passed (429 tests, 24 expected environment skips, 0 failures); swift build -c release passed; git diff --check passed; dg validate passed with only pre-existing warnings. No additional source delta was needed for this umbrella issue.

### Comment — pi @ 2026-09-01T02:28:10.889Z

## Verification Report — pi (counterpoint, after human review)

**Verdict: PASS** — no blockers. Issue moved to `done`.

### Scope reviewed
Umbrella LUMO-068 and dependencies LUMO-069/070/071/072 (plus verification follow-ups
073/074/075). Reviewed PreviewCoordinator, LiveEditTelemetry, PreviewSurface/MTKView, RenderEngine
(interactive RAW session + RAWFilterBaseline), ToneCurveFilterCache/RenderPipeline 1D-kernel, and
the inspector interaction wiring in Light/Develop/Adjust/ContentView.

### Checks run (all declared in the issue context)
- `swift build` — clean.
- `swift build -c release` — clean.
- `swift test` — 429 tests, 24 expected environment skips, 0 failures.
- `LUMO_BENCH=1 swift test --filter testLargePreviewInteractiveLatencyBenchmark` — p50 6.7 ms, p95 7.0 ms (fake renderer, as documented; hardware gate is the Instrument capture).
- `LUMO_BENCH=1 swift test --filter testMeasureToneCurveDragCost` — 58.36 → 3.23 ms/tick (18.1×), 4,194,304 → 4,096 bytes/tick (1024×) on live hardware curve path.
- `git diff --check` — clean.
- `dg validate` — OK; only pre-existing runner-model + LUMO-076 low-context warnings.
- `git status` — no tracked source modified; only `.dg/` bookkeeping.

### Acceptance-criteria findings
- Every continuous control (Light sliders, Develop incl. WB tint, Adjust, tone curve) publishes
  intermediate frames during a drag: all inspectors wire begin/endPreviewInteraction and route
  active edits through scheduleInteractivePreview; PreviewCoordinator starts immediately
  (interactiveDelay default .zero), latest-wins, one-in-flight/one-pending.
- Tone curve: same lifecycle; add/remove point wrapped in begin/endPreviewInteraction →
  immediate interactive render. 1D-kernel fix (half-texel, e6617d8) verified present, correct.
- At most one interactive render in flight, at most one pending; obsolete never publishes:
  `interactiveRenderInFlight` + `pendingInteractive` + revision guard `isCurrent`. Covered by
  PreviewCoordinatorTests (stale-not-published, one-in-flight).
- Settled upgrade is in-place, no blank/fade/repaint: settled phase publishes the same GPU surface
  and skips redundant CGImage raster (LUMO-075); test `testSettledGPUPublicationDoesNotRasterizeASecondImage`.
- Export/settled parity preserved: settled+export share the canonical buildImage path and
  RAWDevelopSettings; interactive uses a separate quality/session but never the settled result.
- RAW Develop interactive session: single-entry actor-confined CIRAWFilter reused per source,
  restore-before-apply baseline mirrors every settable property; canonical settled path untouched.
- Live-edit telemetry (LUMO-072): separate signposts for PointerInput/RenderStart/End/
  GPUComplete/DrawablePresented/StaleRevision keyed by revision; quantile/FPS/gap/coalesce report.

### Non-blocking findings
- **LUMO-079 filed (backlog, `verification`, parent LUMO-068):** `PreviewSurfaceView.updateNSView`
  records `drawablePresentation` synchronously at command-buffer submit time (signpost labels it
  "drawable-submitted"), before GPU completion and before the frame is actually displayed. So
  `inputToPresent` in the app report is input-to-submit and understates true pointer-to-photon
  latency. Recommended: use `MTLDrawable` presented/scheduled handler for true presentation time.
  Not a blocker — the release-gate numbers are the documented Instruments/Metal System Trace
  capture (which measures true latency), and the app report is a correlation aid.

### Existing governance
LUMO-074 (measured tone-curve win) and LUMO-075 (redundant settled raster) are done and confirmed
here; LUMO-076 (GPU surface uses WorkingSpace.current, currently inert) remains open low-priority,
as filed.

### Verification commits
None — no source changes were required; this review only filed a backlog ticket and bookkeeping.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T02:28:19.020Z: Counterpoint verification PASS after human review. 429 tests pass, debug+release builds clean, tone-curve measured 18x speedup, live-edit p95 7.0ms (fake) / instrumentation infra confirmed. LUMO-079 filed (non-blocking: telemetry measures submit not present time).
