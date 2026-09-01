---
id: LUMO-072
title: Gate live editing on real pointer-to-photon latency across Light, Develop, and Adjust
type: task
status: done
priority: urgent
verification_model: haiku
labels:
  - mvp
  - performance
  - live-preview
  - verification
created: 2026-08-31T22:56:14.305Z
updated: 2026-09-01T01:22:49.306Z
depends_on:
  - LUMO-069
  - LUMO-070
  - LUMO-071
order: w
board: product
commits:
  - 20f07bc
---

## Objective

Replace fake-renderer confidence with repeatable real-GPU pointer-to-present measurements and make
live preview performance a release gate.

## Context

The existing `PreviewCoordinator` benchmark reports roughly 6-7 ms for a 60 MP-class request, but
uses `FakeRenderEngine`; the source extent is realistic while no RAW decode, Core Image graph,
rasterization, UI publication, or display presentation is measured. `docs/INSTRUMENTS.md` targets
slider-input-to-render completion at 50 ms, but does not measure the presented frame or exercise
every Light, Develop, Adjust, and curve path. LUMO-063 recorded a real 1600 x 1200 direct raster cost
near 205.5 ms for its generated standard-image case, showing why the fake number cannot close this
requirement.

## Acceptance criteria

- [ ] Capture pointer event timestamp, document revision, render start/end, GPU completion, and
  drawable presentation for the same revision; report true input-to-present latency and frame gaps.
- [ ] Benchmark every Light slider, the tone curve, every available Develop slider category, and
  every Adjust slider on representative 24 MP and 40-60 MP RAW plus large standard images.
- [ ] Record p50/p95/p99 input-to-present latency, delivered FPS, dropped/coalesced values, maximum
  stale-revision age, CPU/GPU time, render dimensions, allocations, and memory growth.
- [ ] On the reference Apple Silicon Mac, Light/Adjust/curve p95 is at most 33 ms and RAW Develop p95
  is at most 50 ms during a sustained drag; no published-frame gap exceeds 100 ms and no stale
  revision is ever presented.
- [ ] The first changed frame appears before mouse-up, and a one-second drag produces multiple
  intermediate presented frames for every continuous control.
- [ ] Mouse-up-to-settled p95 is at most 200 ms, with no blank/fade/layout refresh or visual flash
  between interactive and settled frames.
- [ ] Store the hardware, OS, commit, source files/resolutions, warm/cold state, trace, and summary so
  results are reproducible. CI keeps deterministic orchestration tests but does not substitute them
  for this hardware gate.

## Implementation notes

Extend the existing Points of Interest vocabulary and `docs/INSTRUMENTS.md`; use signpost revision
IDs or another privacy-safe correlation token. Run before/after captures for LUMO-069 through
LUMO-071. If a decoder-specific control cannot meet the numeric gate, document the exact source,
decoder, and measured bottleneck and create a targeted blocker rather than weakening all thresholds.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T01:22:49.304Z: Implemented revision-correlated live-edit telemetry across PointerInput, RenderStart/End, GPUComplete, DrawablePresented, and StaleRevision signposts. PreviewCoordinator records input/render timing and stale/coalesced revisions; the Metal surface records drawable submission and command-buffer GPU completion. Added quantile/FPS/frame-gap/render-dimension reporting, coverage tests, and an Instruments release-gate matrix for every Light, curve, available Develop, and visible Adjust control across representative RAW/standard sources. Verification: swift test (429 passed, 24 expected environment skips), swift build -c release, git diff --check, dg validate (pre-existing runner/context warnings only). Numeric p95 gate results remain a required reference-Mac Instruments capture and are not claimed from CI.
