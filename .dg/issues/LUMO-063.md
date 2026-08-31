---
id: LUMO-063
title: Interactive/live preview now round-trips through PNG encode+decode on every render
type: task
status: backlog
priority: medium
labels:
  - verification
created: 2026-08-31T13:15:02.990Z
updated: 2026-08-31T14:24:36.947Z
order: zzxh
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
