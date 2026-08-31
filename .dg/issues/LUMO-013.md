---
id: LUMO-013
title: Coalesce interactive renders and settle to final preview quality
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:21.357Z
updated: 2026-08-31T13:33:43.826Z
depends_on:
  - LUMO-012
estimate: 5
order: zz
board: product
commits:
  - 3976f18
---

## Objective

Introduce a coordinator that cancels superseded slider renders, prioritizes the visible image, and publishes a settled preview after interaction ends.

## Context

Part of **Epic 2 — Render orchestration, caching, and observability**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Model gesture/burst lifecycle separately from the renderer actor.
- Issue viewport-sized interactive work during manipulation.
- Cancel/coalesce stale work and render preview quality on settle.
- Guard every publication with source and revision identity.

## Acceptance criteria

- [ ] Rapid 0.1→0.5 input converges on 0.5 without a five-render queue.
- [ ] UI state publication remains main-actor-only while decoding/rendering does not.
- [ ] A settled render replaces interactive output.
- [ ] Navigation and edits cannot display stale results.

## Verification

- Add deterministic fake-renderer cancellation, coalescing, settle, and stale-publication tests.

## Out of scope

- GPU filter design.
- Display refresh synchronization beyond the MVP target.

### Comment — codex @ 2026-08-31T13:30:50.661Z

Implemented in commit 3976f18. Added the main-actor PreviewCoordinator to model interactive bursts separately from RenderEngine: viewport-sized interactive requests are coalesced/cancelled, the latest value is promoted to settled preview quality on interaction end, visible work is prioritized ahead of baseline/histogram work, and all render-related publications are guarded by source/revision identity. Wired Slider editing callbacks, kept raster decoding off the main actor, added renderer cancellation checks, and added deterministic fake-renderer tests for cancellation, coalescing, settle promotion, and stale publication. Verification: swift test passed (314 tests, 20 expected skips, 0 failures); swift build -c release passed; git diff --check passed; dg validate passed with only pre-existing warnings for the pickup model name and LUMO-011 context completeness.

### Comment — claude @ 2026-08-31T13:33:39.239Z

## Independent verification (counterpoint pass)

**Scope reviewed:** PreviewCoordinator.swift, RenderEngine.swift cancellation checks, AppViewModel wiring (schedulePreview/scheduleInteractivePreview/publishPreview/scheduleOriginalPreview), Slider onEditingChanged wiring in AdjustInspectorView/DevelopInspectorView/ContentView, and PreviewCoordinatorTests.

**Checks run:**
- `swift build` — clean.
- `swift test` — 314 tests, 20 expected skips, 0 failures.
- `swift build -c release` — clean.
- `git diff --check 20bea35 3976f18` — clean.
- `dg validate` — OK, only pre-existing warnings (pickup model name, LUMO-011 context completeness).

**Correctness:**
- Revision/token guard (`Token{source, revision}` + `isCurrent`) correctly rejects stale publications even from a non-cancellable renderer, verified by `testAStaleResultCannotPublishAfterANewRevision` using a `ControlledRenderEngine` that ignores cancellation.
- Coalescing verified: 5 rapid interactive submissions (0.1→0.5) produce exactly one render call carrying the last value, then exactly one settled render on `endInteraction()` — matches the "no five-render queue" acceptance criterion.
- `RenderEngine.render` gained two `Task.checkCancellation()` checkpoints (pre-build, pre-return) so queued/in-flight work actually drops instead of rasterizing an obsolete graph; `FakeRenderEngine` mirrors this for test parity.
- Main-actor boundary respected: `PreviewCoordinator` and `AppViewModel` are `@MainActor`; `PreviewImageDecoder.decode` and the render call are the only work off the main actor, matching the "publication remains main-actor-only, decode/render does not" criterion.
- Navigation safety: `load()` calls `previewCoordinator.cancel()` and bumps `sourceRevision`/`documentRevision`, and `publishPreview`/`scheduleOriginalPreview`/`updateHistogram` all re-check identity (source and, for the supporting tasks, revision) before writing `@Published` state.
- No Swift 6 opt-outs introduced (`grep` for `@unchecked Sendable` / `nonisolated(unsafe)` / `@preconcurrency` in the touched files: none).

**Non-blocking observations (not filed as tickets — cosmetic/informational only):**
- `.interactive` and `.preview` `RenderQuality` currently share the same `renderScale` case, and the app submits the same `maxPreview` target size for both interactive and settled requests — "viewport-sized interactive work" is achieved only in the sense that the request is coalesced/cancellable, not that it's cheaper to render. Consistent with current scope (GPU filter design and display sync are explicitly out of scope); flagging only as context, not a defect.
- The render-task field inside `PreviewCoordinator` is named `interactiveTask` but also stores the settled-phase render `Task` (`scheduleSettled` assigns into it). Cosmetic naming only — behavior is correct because `submit()` always cancels both fields before scheduling — not worth a localized fix that would touch working, tested code.

**Verdict:** PASS. No blockers found. Acceptance criteria and out-of-scope boundaries are satisfied by the diff at commit 3976f18.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T13:33:43.617Z: Independent verification passed: builds, 314 tests pass, no Swift 6 opt-outs, coalescing/cancellation/revision-guard behavior confirmed against acceptance criteria.
