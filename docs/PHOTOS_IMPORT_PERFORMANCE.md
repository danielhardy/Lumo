# Photos import performance

Photos imports are now streamed one picker item at a time. The transfer task keeps only the
currently awaited payload outside `ImageCollection`; each successful payload is inserted
immediately, the first successful source begins decoding immediately, and thumbnail work remains
on the existing four-worker/24-queued bounded scheduler. A failed or cancelled item does not remove
successful items already published.

The import path emits these Points of Interest intervals under
`com.lumo.app` / `workflow`:

- `PhotoTransfer` — one `PhotosPickerItem.loadTransferable` call.
- `Decode` with `quality=photosImport` — the first imported source's eager decode. RAW data uses
  `CIRAWFilter(imageData:identifierHint:)`, while standard data uses orientation-aware `CIImage`.
- `PhotoThumbnail` — the in-memory thumbnail path, including its bounded byte-cache lookup.
- `PhotoCollectionInsert` — source-record insertion plus metadata/thumbnail admission for one item.

## Repeatable before/after capture

Use a licensed representative RAW outside the repository. The repository deliberately does not
include a 40–60 MP camera file. On the reference Mac, run:

```sh
LUMO_PHOTOS_BENCHMARK=1 \
LUMO_PHOTOS_RAW=/absolute/path/to/representative.dng \
swift test --filter PhotosImportPerformanceTests
```

The opt-in test prints `before_transfer_ms`, `after_transfer_ms`, `decode_ms`, `thumbnail_ms`,
`before_collection_insert_ms`, and `after_collection_insert_ms` for a three-item selection proxy.
Capture the same scenario in Instruments with Points of Interest plus Allocations/VM Tracker.
Record Mac/chip/memory, OS, commit, RAW dimensions, cold/warm state, peak resident memory, and the
slowest interval. Do not use the generated test's numbers as a universal hardware claim: its
purpose is repeatability and regression detection.

The original implementation transferred all three payloads before collection insertion, so no
item could become usable during transfer and the temporary array retained the full selection.
The current implementation publishes each item at transfer completion; full original bytes remain
retained once per imported source because later edits and RAW re-development require them.
