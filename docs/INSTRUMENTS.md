# Lumo Instruments capture recipe

Lumo's render workflow emits Points of Interest signposts under subsystem
`com.lumo.app`, category `workflow`. The signpost names are stable across builds:
`Launch`, `Scan`, `Decode`, `Render`, `Cache`, `PhotoSwitch`, `Histogram`, and
`Export`, and `LiveEdit`. Cache outcomes are events named `CacheHit` and `CacheMiss`; cancelled
and coalesced work is counted by `Cancellation` and `Coalesced` events. LiveEdit emits
`PointerInput`, `RenderStart`, `RenderEnd`, `GPUComplete`, `DrawablePresented`, and
`StaleRevision`. Each carries a privacy-safe source token, quality, and document revision.

The `source` argument is a 16-character SHA-256 token derived from the source's
existing cache fingerprint. It is useful for grouping one photo's intervals but
does not contain a path, filename, or metadata. `quality` is one of
`thumbnail`, `interactive`, `preview`, `fullResolution`, or `export`, which
keeps live editing separate from settled preview and export work.

## Capture steps

1. Build the `Lumo` scheme in Release configuration. Use a clean launch for a
   cold-cache run; relaunch without clearing caches for a warm-cache run. Record
   the Mac model, OS, build commit, source format/resolution, and whether the
   LUT folder was already scanned.
2. Open **Instruments**, choose **Points of Interest** and **Time Profiler**,
   select Lumo as the target, and press Record before launching the app.
3. For launch and scan, let the app restore or choose a source folder and a LUT
   folder. Stop after the first image and its filmstrip have appeared. In the
   Points of Interest timeline, inspect `Launch` and `Scan`; expand `Decode`
   and `Render` to separate first-pixel work from folder work.
4. For photo-switch latency, select an image, wait for its settled `preview`,
   then step to the next image with `Right Arrow` (repeat in both directions).
   Compare the `PhotoSwitch` interval and the first `Render` interval. Repeat
   once after returning to the first image to capture a warm developed-source
   and thumbnail cache case.
5. For live-edit latency, open Light, Develop, Adjust, and Effects in turn. Drag every
   Light slider, the tone curve, every available Develop slider, and every visible
   Adjust slider continuously for at least one second. Join `PointerInput` to
   `DrawablePresented` by revision for input-to-present latency; use `GPUComplete`
   to separate GPU completion from display scheduling. Count `Coalesced` and
   `StaleRevision` events and compare cache events for the same source token.
6. Open the Info inspector and repeat the slider capture with the histogram
   visible. Confirm `Histogram` work follows the settled visible render and does
   not dominate the interactive interval.
7. Export one edited image and then use **Export All** for a representative
   folder. Inspect `Export` intervals and `quality=export`; do not combine export
   throughput with interactive latency.

Use the **Points of Interest** detail view to inspect interval duration and event count.
`PreviewCoordinator.telemetry.report()` supplies p50/p95/p99 input-to-present latency,
delivered FPS, frame gaps, coalescing, stale-revision age, and render dimensions.
Use Metal System Trace for GPU time and Allocations/VM Tracker for allocations and memory growth.
Save the `.trace` and this value-only summary with the scenario notes.

## Release-gate capture matrix

Run each row cold and warm on the reference Apple Silicon Mac, using representative 24 MP and
40–60 MP RAW files plus a large standard image. A one-second drag must produce multiple
`DrawablePresented` revisions before mouse-up.

| Surface | Controls | Source classes |
| --- | --- | --- |
| Light | Exposure, Contrast, Highlights, Shadows, Whites, Blacks, tone curve | 24 MP RAW, 40–60 MP RAW, large standard |
| Develop | Every available decoder control | 24 MP RAW, 40–60 MP RAW |
| Adjust | Every visible adjustment control | 24 MP RAW, 40–60 MP RAW, large standard |
| Effects | Texture, Clarity, Dehaze, Vignette, Grain | 24 MP RAW, 40–60 MP RAW, large standard |

Store Mac/chip/memory, OS, commit, source dimensions, render dimensions, decoder name/version,
warm/cold state, trace path, telemetry summary, and dropped/coalesced values. XCTest orchestration
is deterministic coverage, not a hardware-gate result. If a decoder-specific control misses its
threshold, record its source, decoder, and bottleneck and file a targeted blocker.

## Initial targets to validate

These are proposed release-gate thresholds, not claims about the current build.
Measure cold and warm cases separately, and report p50/p95 over at least ten
photo switches or slider gestures where practical.

| Measurement | Target |
| --- | ---: |
| Warm standard-photo switch to first interactive render | ≤ 100 ms |
| Warm RAW-photo switch to first interactive render | ≤ 250 ms |
| Light/Adjust/curve input to drawable presentation (p95) | ≤ 33 ms |
| RAW Develop input to drawable presentation (p95) | ≤ 50 ms |
| Slider release to settled preview completion | ≤ 200 ms |
| Histogram completion after the settled render | ≤ 100 ms |
| Repeated identical preview requests | cache hit; no full-resolution cache entry |
| Published-frame gap | ≤ 100 ms; no stale revision |
| Main-thread stall in the core switch/slider path | no unexplained stall > 100 ms |

The thresholds are diagnostic targets: profiling may show that a source class,
hardware generation, or Core Image behavior needs a documented exception. Do
not mark a target as met from unit tests alone.
