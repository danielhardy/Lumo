---
id: LUMO-012
title: Expand rendering into explicit request, result, and quality tiers
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:21.006Z
updated: 2026-08-31T13:15:42.960Z
depends_on:
  - LUMO-006
estimate: 5
order: zx
board: product
---

## Objective

Evolve preview/full scale calls into a UI-independent request API supporting thumbnail, interactive, preview, full-resolution, and export qualities.

## Context

Part of **Epic 2 — Render orchestration, caching, and observability**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define Sendable RenderRequest, RenderResult, and RenderQuality values around existing ImageSource/EditDocument behavior.
- Keep one adjustment model and one deterministic pipeline for every quality.
- Document output extent, color space, and pipeline ordering contracts.

## Acceptance criteria

- [ ] All five quality tiers are represented without duplicate edit models.
- [ ] The rendering API has no SwiftUI/AppKit view dependency.
- [ ] Neutral requests preserve orientation and expected extent.
- [ ] Preview and export differ only through explicit quality/output policy.

## Verification

- Adapt fake renderer and add request contract/parity tests.

## Out of scope

- UI scheduling.
- New image adjustments.

### Comment — codex @ 2026-08-31T13:12:07.112Z

Implemented in commit 49b79e9.

Verification: `swift test` passed (312 tests, 20 expected RAW/benchmark skips, 0 failures); `swift build -c release` passed; `dg validate` passed with pre-existing warnings only.

LUMO-012 acceptance coverage:
- Added Sendable `RenderRequest`, `RenderResult`, `RenderQuality`, and explicit raster/encoded output policy.
- Represented thumbnail, interactive, preview, fullResolution, and export tiers using one `EditDocument` and one deterministic pipeline.
- Preview and export now call the request API directly; no UI framework enters the renderer boundary.
- Neutral oriented renders preserve upright extent; results report encoded extent and working color space.
- Adapted the fake renderer and added request contract/parity tests; documented output, color-space, and pipeline-ordering contracts in `docs/PHASE2_SPEC.md`.

### Comment — claude @ 2026-08-31T13:15:39.481Z

## Verification report (independent counterpoint review)

**Verdict: pass, non-blocking finding filed as LUMO-063.**

Reviewed commit 49b79e9 (feat: unify render requests across quality tiers) against the LUMO-012
scope and acceptance criteria.

Checks run:
- `swift build` — clean
- `swift test` — 312 tests, 20 expected RAW/benchmark skips, 0 failures (matches implementer's report)
- `dg validate` — OK (pre-existing warnings only: agent model name, LUMO-005/LUMO-011 context completeness)
- `git status --porcelain` — clean tree apart from `.dg` symlink

Acceptance criteria check:
- All five `RenderQuality` tiers (`thumbnail`, `interactive`, `preview`, `fullResolution`, `export`)
  represented by one `EditDocument`/`RenderRequest`, one pipeline (`RenderPipeline.buildImage`) — confirmed.
- `RenderRequest`/`RenderResult`/`RenderQuality`/`RenderOutput` are plain value types with no
  SwiftUI/AppKit import — confirmed by inspection of `Sources/LumoKit/Models/RenderRequest.swift`.
- Neutral/oriented renders preserve upright extent and report it via `RenderResult.extent` —
  covered by `RenderRequestTests.testNeutralRenderBakesOrientationAndReportsTheEncodedExtent`.
- Preview and export differ only via explicit `quality`/`output`, same pixels —
  covered by `RenderRequestTests.testPreviewAndExportParityUsesExplicitQualityAndOutputPolicies`.

Finding (non-blocking, filed as **LUMO-063**, label `verification`):
`RenderEngine.render(_:)` now encodes every `.raster` output to PNG inside the actor and the caller
decodes it back (`CGImageSourceCreateImageAtIndex` / `NSImage(data:)`), because `CGImage` isn't
`Sendable`. This lands on the interactive/live-edit preview hot path
(`AppViewModel.schedulePreview()` / `scheduleOriginalPreview()`, debounced per slider tick, up to
1600×1200) where the old `makeCGImage` produced a `CGImage` directly via `context.createCGImage`
with no encode/decode round trip. `docs/CODE_REVIEW.md` already documents a prior fix to this exact
preview path for main-thread-blocking performance, so this is a regression against a path the
project has previously cared about — not a correctness bug, and not something a localized
verification-pass fix can safely resolve without touching the `RenderResult`/`RenderEngining`
contract LUMO-012 just established. Filed as a follow-on with a concrete acceptance bar (measure the
actual per-frame cost; give the interactive path a cheaper representation if it's perceptible).

No other correctness, security, or maintainability issues found. `RenderRequest.renderScale`
defaulting `targetSize == nil` downsampled tiers to `source.nativeExtent` (i.e., no downsampling) is
a minor design smell worth a comment but not wired to any live call site today — not filed
separately.

No blockers. No verification commits (fix was out of localized-fix scope; tracked as LUMO-063 instead).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
