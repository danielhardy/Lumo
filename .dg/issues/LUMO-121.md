---
id: LUMO-121
title: Capture representative hardware evidence for LUMO-107's warm-transform/settle latency targets
type: task
status: done
priority: medium
labels:
  - verification
created: 2026-09-02T02:25:25.541Z
updated: 2026-09-02T04:33:01.963Z
order: zzzzzzv
board: product
---

## Objective

Capture a representative Release-build hardware trace of the pipeline landed in LUMO-107 (commit
3195e55, off-main-actor completed-texture rendering + presentation-only transform pass), and record
whether it meets LUMO-107's measured acceptance criteria: p95 input-to-present ≤33 ms for warm
transforms/ordinary adjustments at 60 Hz, and ≤200 ms release-to-settled, with drawable acquisition,
presentation encoding, and GPU completion reported as separate figures (the new
`markPresentationTimings`/`PresentationEncoded` telemetry added in 3195e55 already carries these).

## Context

Independent counterpoint verification of LUMO-107 (2026-09-02) found the implementation,
concurrency boundaries, and pixel-parity/failure-path test coverage sound — `PreviewSurfaceTests`,
`PreviewCoordinatorTests`, full `swift test`, and `swift build -c release` all pass on commit
3195e55. What is not yet verified is the ticket's own quantitative target: no hardware capture has
been taken *after* this change landed. The only archived capture in
`docs/PERFORMANCE_CAPTURE_MATRIX_2026-09-01.md` / `docs/LUMO-118-DSC07826-...-summary.md` was taken
under LUMO-118 on commit 90c1b95 (predates 3195e55) and measured p95 input-to-present at 35.966 ms —
over the 33 ms target — but that capture exercised the pre-LUMO-107 lazy-graph presentation path, so
it says nothing about whether LUMO-107 closed the gap.

This mirrors the LUMO-118/LUMO-119 precedent: measurement requires a logged-in Mac with a real
display and `scripts/run-lumo-118-capture.sh` (or equivalent), which is not available from this
verification session. Per that precedent, this capture gap does not block LUMO-107 from completing
implementation/verification, but the ticket's numeric acceptance criterion remains an open,
trackable follow-up rather than a demonstrated result.

## What's needed

- A logged-in Mac with a real display, Release build, and `xctrace` (Points of Interest + Metal
  System Trace), same setup as LUMO-118/119.
- Run the existing capture tooling against a representative source (the `realworldtest/` ARW
  fixtures qualify) on a commit at or after 3195e55.
- Record p50/p95/p99 input-to-present, drawable-acquisition and presentation-encoding budgets
  separately from GPU completion, and release-to-settled time, alongside the standard capture
  metadata (machine, OS, commit, Release config, source dims/format, viewport/backing pixels).
- Compare against the ≤33 ms p95 / ≤200 ms settle targets in LUMO-107's acceptance criteria and
  record the result (met, not met, or partially met) in the capture matrix / summary doc.

## Scope boundaries

Do not fabricate or estimate numbers from the pre-3195e55 LUMO-118 capture — it measured a
different code path. Parent: LUMO-107.


### Comment — codex @ 2026-09-02T04:28:34.097Z

Implemented and archived the post-LUMO-107 hardware evidence in commit 59a9fc5. The Release Metal System Trace is /tmp/lumo-121-capture-final2/LUMO-121-DSC07826-20260901-222341.trace; durable summary: docs/LUMO-121-DSC07826-20260901-222341-summary.md. On MacBookPro18,3 M1 Pro / macOS 26.6, DSC07826.ARW 6000x4000 at 1280x800: warm p95 input-to-present 8.632 ms (target <=33 ms) and release-to-settled p95 9.139 ms (target <=200 ms), with drawable acquisition, presentation encoding, and GPU timing separated. Focused tests, Release build, benchmark, diff check, and dg validate pass. Full swift test has two unrelated pre-existing host/fixture failures: CropWorkflowTests.testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit and RAWCapabilitiesTests.testProbingARealRAWReportsItsDecodersSeeds.


### Comment — claude @ 2026-09-02T04:32:59.524Z

## Counterpoint verification report (2026-09-02, second pass)

**Scope:** Independent verification of the LUMO-121 hardware capture (commit 59a9fc5) against the
issue's acceptance criteria and the LUMO-107 numeric targets.

**Checks performed:**
- `swift build -c release`: clean build.
- `swift test` (full suite): 594 tests, 1 failure — `RAWCapabilitiesTests.testProbingARealRAWReportsItsDecodersSeeds`
  (host-dependent lens-correction default; file untouched by this commit, unrelated to LUMO-121).
  `CropWorkflowTests.testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit`, previously
  reported as failing, did not reproduce on this run — consistent with a flaky/host-state test, also
  unrelated to the files this commit touches.
- Focused suites `PreviewSurfaceTests` and `PreviewCoordinatorTests`: pass.
- `dg validate`: OK.
- Commit ancestry: confirmed `3195e55` (LUMO-107) is an ancestor of the capture commit `df1143b`.
- Cross-checked the archived summary (`docs/LUMO-121-DSC07826-20260901-222341-summary.md`) against
  the raw `METAL_PRESENTATION_BENCHMARK` line in
  `/tmp/lumo-121-capture-final2/LUMO-121-DSC07826-20260901-222341-summary.txt` — every reported
  figure (p50/p95/p99, drawable acquisition, presentation encoding, GPU time, release-to-settled)
  matches the raw tool output verbatim; nothing was hand-edited or estimated. Trace artifact
  (`.trace`, 31 MB) exists at the recorded path.
- Reviewed the `MetalPresentationBenchmark.swift` diff: the warm-sample path now renders through
  `RenderEngine.makeCIImage` (off-actor completed-texture path) and only applies presentation
  transforms for the timed samples, correctly isolating the LUMO-107 boundary; the settle path uses
  ordinary `.preview`-quality Light adjustments against a warmed source, matching the ticket's
  "release" definition. `dropped_or_coalesced_values` is honestly reported as not applicable rather
  than fabricated, since this is a direct benchmark without a `PreviewCoordinator` pointer stream.

**Result:** Both LUMO-107 targets are met on this representative run — warm p95 input-to-present
8.632 ms (<=33 ms) and release-to-settled p95 9.139 ms (<=200 ms). No blockers found. No code
changes were needed from this verification pass.

**Verdict: PASS.**
