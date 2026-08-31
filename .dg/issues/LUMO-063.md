---
id: LUMO-063
title: Interactive/live preview now round-trips through PNG encode+decode on every render
type: task
status: done
priority: medium
labels:
  - verification
created: 2026-08-31T13:15:02.990Z
updated: 2026-08-31T15:23:34.160Z
order: n
board: product
branch: agent/lumo-063
commits:
  - 86ba0ee
  - 86ba0ee
---

## Objective

Restore a zero-copy (or otherwise cheaper) path from `RenderEngine` to the on-screen `NSImage` for
the interactive/live-edit preview loop, without reopening `RenderRequest`/`RenderResult`'s public
shape.

## Context

Found during LUMO-012 verification (non-blocking). LUMO-012 (commit 49b79e9) collapsed
`RenderEngining.makeCGImage`/`encode` into a single `render(_ request: RenderRequest) async throws
-> RenderResult`. Because `CGImage` is not `Sendable`, every `.raster` output is now encoded to PNG
bytes inside the actor (`context.pngRepresentation`) and re-decoded on the caller's side
(`CGImageSourceCreateImageAtIndex` / `NSImage(data:)`), even for the debounced live-preview path.

Call sites: `AppViewModel.schedulePreview()` and `AppViewModel.scheduleOriginalPreview()`
(`Sources/LumoKit/ViewModels/AppViewModel.swift:672-716`), which fire on every slider-drag tick
(debounced) up to `maxPreview` = 1600×1200, and the default `RenderEngining.makeCGImage` shim in
`Sources/LumoKit/Models/RenderEngine.swift`.

Previously `RenderEngine.makeCGImage` called `context.createCGImage(...)` directly and handed the
result out via `sending CGImage?` — no encode, no decode. `docs/CODE_REVIEW.md` records that this
exact preview path was already the subject of a prior main-thread-blocking performance fix
(`renderPreview` / `Task.detached`), so it's a path this project has previously cared about keeping
fast; adding a full PNG encode + decode on every debounced edit tick is a regression against that
history even though it introduces no correctness bug (all LUMO-012 tests and acceptance criteria
pass, and `docs/PHASE2_SPEC.md` §4.5 already documents dropping the old "zero-copy" property as the
explicit cost of `CGImage` non-`Sendable`-ness).

Not blocking LUMO-012: the API contract (Sendable `RenderRequest`/`RenderResult`, no
SwiftUI/AppKit dependency in the renderer) is what the acceptance criteria asked for, and changing
the raster representation is a broader change than a verification-pass localized fix allows.

## Acceptance criteria

- [ ] Measure the actual per-frame cost added by the PNG encode+decode round trip at `maxPreview`
      size (1600×1200) and confirm whether it is perceptible during a slider drag.
- [ ] If it is, give the interactive/live-preview path a cheaper way to get pixels out of
      `RenderEngine` (e.g. a raw bitmap `Data` representation instead of PNG, or a way to keep the
      `CGImage` on the actor side and hand out a `sending CGImage?` for this one call shape) without
      reintroducing `CGImage`/`CIImage` into `RenderRequest`/`RenderResult` or breaking their
      `Sendable` contract.
- [ ] Export and thumbnail/background paths, which are not latency-sensitive, may keep the PNG/
      encoded path as-is.

## Implementation notes

Keep `RenderRequest`/`RenderResult` as the UI-independent, Sendable renderer boundary — don't
reintroduce a view-layer type into `RenderEngining`. The likely fix is either a raw-bitmap
`RenderOutput` case decoded without PNG's compression pass, or a separate low-latency accessor on
`RenderEngining` reserved for `.thumbnail`/`.interactive` quality that still funnels through the same
`RenderRequest`/pipeline construction.

### Comment — codex @ 2026-08-31T15:16:30.802Z

Implemented in commit 0b0e2a7. Added a RenderEngining.makeCGImage(RenderRequest) display accessor with a direct actor-local CIContext.createCGImage implementation and a PNG-backed default fallback for test/future conformers. PreviewCoordinator and the comparison preview now use the accessor, so interactive/live frames avoid PNG encode+ImageIO decode while RenderRequest/RenderResult and export encoding remain unchanged. Extended PreviewCostBenchmark: at 1600x1200 on a 6000x4000 standard image, direct rasterization measured 205.5 ms/render versus 234.3 ms/render for PNG encode+decode, an added 28.8 ms (1.14x), above a 60 Hz frame budget and plausibly perceptible during slider drag. Verification: focused preview/engine tests passed (31, 1 expected skip); full swift test passed (332, 20 expected skips); swift build -c release passed; dg validate passed with only pre-existing warnings.

### Comment — claude @ 2026-08-31T15:18:20.936Z

Verification report (independent counterpoint review, agent claude, session 01MTHDSQ5IRQW1GVBG):

Reviewed commit 0b0e2a7 against the acceptance criteria and re-ran all declared checks.

- Design: RenderEngining gains makeCGImage(_ request:) -> sending CGImage?, with a PNG-backed
  default (source-compat for other conformers) and a RenderEngine override that rasterizes directly
  from the actor-local CIContext, sending only the CGImage out. RenderRequest/RenderResult remain
  unchanged and Sendable; export/thumbnail paths still use render()/pngRepresentation. Matches the
  "separate low-latency accessor" option from the implementation notes without reopening the
  renderer's public shape.
- Cancellation/error semantics preserved: PreviewCoordinator's guard ordering (Task.isCancelled check
  before the nil-image branch) reproduces the prior do/catch's silent-cancel vs onFailure split.
  Verified no stale references to the removed PreviewImageDecoder or RenderResult.quality remain.
- Checks re-run independently: swift build (debug) clean; swift test focused
  (PreviewCoordinatorTests/RenderEngineTests/AppViewModelTests) 38/38 passed; full swift test 332
  passed, 20 expected skips, 0 failures; swift build -c release clean; dg validate OK (only
  pre-existing warnings: agents.pickup.runner model name, LUMO-017/LUMO-064 context completeness).
- Benchmark numbers in the implementation comment (205.5ms direct vs 234.3ms PNG round-trip,
  +28.8ms/1.14x at 1600x1200) are consistent with the acceptance criteria's ask to measure and act on
  the per-frame cost.
- One doc-only gap found and fixed in this pass: docs/PHASE2_SPEC.md §4.5 still said CGImage is
  "decoded from raster result bytes only after the renderer boundary" for all cases, which is now
  false for the interactive path. Corrected in commit 86ba0ee to describe both the export/default path
  and the new makeCGImage accessor.

No blockers found. Verification passes.

### Comment — codex @ 2026-08-31T15:18:23.852Z

Automatic merge into `main` failed: fatal: cannot do a partial commit during a merge.

### Comment — claude @ 2026-08-31T15:19:16.289Z

dg issue complete's auto-merge-into-main step failed:

  Merge skipped/failed: fatal: cannot do a partial commit during a merge.

This is not a defect in LUMO-063's fix — the main worktree already has an unrelated merge in
progress (agent/lumo-018 -> main, conflicts in ImageCollection.swift/ImageMetadata.swift/new
PhotoAsset.swift, already staged but not committed). That's exactly the scope of LUMO-064, which
already exists and is claimed. Verification for LUMO-063 stands as passed (see prior comment);
leaving status at verification rather than forcing a merge into a checkout that isn't in a clean
state. Re-run `dg issue complete LUMO-063 --commit 86ba0ee` once LUMO-064 lands and main is clean.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T15:18:23.694Z: Independent verification passed: reviewed 0b0e2a7's makeCGImage accessor against acceptance criteria, re-ran full test suite (332 passed/20 skipped), release build, and dg validate — all clean. Fixed one stale doc reference in docs/PHASE2_SPEC.md §4.5 (commit 86ba0ee). No blockers.
