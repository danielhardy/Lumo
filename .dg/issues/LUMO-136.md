---
id: LUMO-136
title: Honor ExportMetadataPolicy in the export encoder (EXIF is dropped even with .preserve)
type: task
status: done
priority: medium
labels:
  - verification
created: 2026-09-02T17:36:10.165Z
updated: 2026-09-02T19:34:10.566Z
depends_on:
  - LUMO-050
order: zzzzzzx
board: product
---

## Objective

Make the export metadata policy have a real effect on the encoded file: with `ExportMetadataPolicy.preserve` (the default), carry source metadata (EXIF/TIFF/GPS as applicable) into the exported file; with `.strip`, write none.

## Context

Found during LUMO-050 (Epic 9) counterpoint verification — non-blocking follow-up.

`ExportOptions.metadata` (`.preserve` / `.strip`) is modeled, validated, and unit-tested as a value, but the encoder path in `RenderEngine.render` never reads it: `CIContext.tiffRepresentation/jpegRepresentation/pngRepresentation` are called with no metadata properties, so **every export today drops all EXIF** (camera, lens, capture date, GPS, copyright). Photographers exporting client deliverables silently lose capture metadata while the UI/default claims `preserve`.

The source metadata is already readable in the package (`ImageMetadata.swift` parses TIFF/EXIF/GPS dictionaries; `ImageDecoder` reads CGImage properties), and `RenderRequest` already carries the `ImageSource`, so the dictionaries can be obtained before the render and passed through the `Sendable` boundary as plain values — `CIImage`/`CGImageSource` need not cross the actor.

Suggested mechanism: switch the encode step to `CGImageDestination` (as `Thumbnails.swift` already does) or pass metadata dictionaries via the CIContext representation options where supported, merging in `kCGImageDestinationLossyCompressionQuality` for JPEG.

## Acceptance criteria

- [ ] With `.preserve`, exported JPEG/TIFF/PNG carry the source's EXIF/TIFF metadata (asserted in tests via Image I/O property round-trip).
- [ ] With `.strip`, exported files carry no source metadata.
- [ ] Orientation handling stays correct (the pipeline bakes orientation into pixels; orientation tags must not be re-applied on top).
- [ ] `swift test` green; no public API outside `LumoKit`'s existing surface changes.

## Out of scope

- Editing or synthesizing metadata that was not in the source (e.g. adding a Lumo software tag can ride along, but no ICC editing).

### Comment — codex @ 2026-09-02T19:28:09.253Z

Implemented and verified in commit 4e701ed. Encoded JPEG/TIFF/PNG exports now use Image I/O, preserve source EXIF/TIFF/GPS dictionaries by default, honor metadata: .strip, preserve JPEG quality, and remove source orientation/dimension tags so upright rendered pixels are not transformed twice. Added round-trip tests for all formats, strip behavior, and orientation. swift test: 637 passed, 14 expected skips.

### Comment — claude @ 2026-09-02T19:34:08.789Z

Counterpoint verification: PASS.

Reviewed commit 4e701ed against the acceptance criteria — correctness, maintainability, security, performance.

Findings:
- `exportMetadata(for:)` correctly copies only the TIFF/EXIF/GPS sub-dictionaries (not the top-level properties dict), so the JPEG/TIFF top-level orientation tag is never carried over; TIFF orientation and Exif pixel-dimension keys are explicitly stripped from the copied dictionaries. Verified this holds for both `.url` and `.data`-backed `ImageSource` (Photos-import path), which the new tests don't exercise directly but the code path is identical.
- `.strip` correctly passes `nil`/empty metadata through `CGImageDestinationAddImage` for all three formats — no source EXIF/TIFF/GPS survives.
- JPEG compression quality is still applied via `kCGImageDestinationLossyCompressionQuality` regardless of policy; TIFF/PNG remain lossless as before.
- No Sendable/actor-boundary issues: `[CFString: Any]` metadata dict stays actor-local, never crosses into app state.
- No new public API surface, no migrations, no third-party deps.

Independent verification run (not reused from the implementer's log):
- `swift build`: clean.
- `swift test`: 637 passed, 14 skipped (RAW-fixture-gated, expected on this machine without `realworldtest/`), 0 failures — matches the implementer's reported numbers exactly.
- `git status --porcelain -- Sources Tests`: clean, no stray edits from this verification pass.

No blockers. No non-blocking follow-ups worth a child ticket — the implementation is scoped tightly to the acceptance criteria and the "out of scope" ICC/synthesized-metadata boundary was respected.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
