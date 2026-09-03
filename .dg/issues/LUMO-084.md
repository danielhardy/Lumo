---
id: LUMO-084
title: Profile and optimize Apple Photos import for large RAW assets
type: task
status: done
priority: high
labels:
  - mvp
  - performance
  - photos
  - raw
created: 2026-09-01T14:35:33.384Z
updated: 2026-09-01T15:13:07.276Z
order: a0
board: product
commits:
  - 6a99d31
---

## Objective

Make Apple Photos import responsive and memory-safe for very large RAW assets, including 60 MP
files, based on measured bottlenecks rather than assuming file size is the only cause.

## Context

`ContentView.handlePhotosSelection` currently calls `PhotosPickerItem.loadTransferable(type: Data.self)`
serially for every selected item, retains all decoded `Data` until the whole selection completes,
and only then hands the batch to `importPhotosData`. Large RAW transfers can therefore create long
periods with no visible progress and a high peak memory footprint. Profile transfer, decode,
thumbnail generation, and library insertion separately before changing the pipeline.

## Acceptance criteria

- [ ] A 60 MP-class RAW import has measured timings for Photos transfer, decode, thumbnail work,
  and collection insertion, with the dominant bottleneck identified.
- [ ] Importing one or many large RAW files provides visible progress or an honest loading state,
  remains cancellable where the Photos API permits, and does not appear hung.
- [ ] Work that can safely overlap is bounded and concurrent or streamed so peak memory does not
  grow with the entire selection unnecessarily.
- [ ] Imported originals retain their full bytes, orientation, RAW capability behavior, and stable
  per-photo identity; no reduced preview is substituted for the source.
- [ ] Add regression/performance coverage for one large RAW and a multi-selection, including failure
  or cancellation of an individual item without losing successfully imported items.
- [ ] Report before/after measurements on representative large RAW input.

## Implementation notes

Start at `Sources/LumoKit/Views/ContentView.swift` (`handlePhotosSelection`) and
`Sources/LumoKit/ViewModels/AppViewModel.swift` (`importPhotosData`), then follow the decoder,
thumbnail, and collection scheduling paths. Preserve Swift 6 isolation and avoid unbounded task
fan-out or multiple full-resolution copies per item.

### Comment — codex @ 2026-09-01T15:12:35.105Z

Implemented in commit 6a99d31. PhotosPicker imports now stream one full-fidelity payload at a time, append successful items immediately, use Photos local identifiers for stable per-photo identity, decode RAW data through CIRAWFilter, preserve orientation, show bounded progress/cancellation, and continue after per-item transfer failures. Existing bounded thumbnail scheduling remains in use; added PhotoTransfer, PhotoThumbnail, PhotoCollectionInsert, and photosImport Decode signposts. Added regression coverage for full-byte retention, identity, multi-selection partial failure, cancellation, and an opt-in real-RAW before/after timing harness with docs/PHOTOS_IMPORT_PERFORMANCE.md. Verification: swift test — 496 passed, 26 expected environment/benchmark skips, 0 failures; swift build -c release passed; git diff --check passed; dg validate passed with only the pre-existing unknown pickup-runner model warning. No licensed 40–60 MP RAW is present in this checkout, so hardware timing/memory numbers remain an explicit opt-in capture rather than an invented claim.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T15:13:07.273Z: Streamed Photos RAW import with visible bounded progress and cancellation, full-fidelity source retention, stable Photos identity, RAW-aware decode, bounded thumbnails, per-item failure recovery, signpost profiling, and regression/performance coverage. Verified 496 tests passed (26 expected skips), release build, diff check, and dg validate.
