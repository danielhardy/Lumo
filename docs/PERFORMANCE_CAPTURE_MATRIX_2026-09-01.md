# Lumo performance capture archive — 2026-09-01

This is the reproducible archive manifest for LUMO-117. It records what was captured and what
cannot be captured from this checkout. Hardware rows are not represented as passing until a Release
build is run on a logged-in reference Mac with the named source file and an Instruments trace.

## Reproduction

```sh
# deterministic checks (CI-safe)
swift test --filter 'ObservabilityTests|PreviewCoordinatorTests'
swift build -c release

# real drawable presentation; requires a logged-in display
LUMO_METAL_BENCHMARK=1 swift test --filter MetalPresentationBenchmark/testRealMetalPresentationBenchmark

# tracing overhead; run with and without an active Instruments recording
LUMO_TRACE_BENCHMARK=1 swift test --filter TracingOverheadBenchmark/testMeasureTracingOverhead
```

The Metal test creates a visible `CAMetalLayer`, renders through the shipping
`RenderEngine.presentationContext`, presents real drawables, and waits for each drawable's
`presentedTime`. Its output includes p50/p95/p99 input-to-presentation latency, worst sample gap,
CPU encode time, GPU command-buffer time, and resident-memory delta. The tracing test prints the
enabled/disabled delta per event. Both tests are opt-in and produce no hardware claim in CI.

## Capture matrix

| Capture ID | Surface / controls | Source | Cache | Supporting work | Status / artifact |
| --- | --- | --- | --- | --- | --- |
| STD-LIGHT | Light: exposure, contrast, highlights, shadows, whites, blacks, curve | large standard image | cold + warm | off + histogram | pending local Release run |
| STD-ADJUST | Adjust: every visible control | large standard image | cold + warm | off + histogram | pending local Release run |
| STD-EFFECTS | Effects: texture, clarity, dehaze, vignette, grain | large standard image | cold + warm | off + histogram | pending local Release run |
| RAW24-DEVELOP | Develop: every decoder control | representative 24 MP RAW | cold + warm | off + histogram | requires licensed local RAW |
| RAW24-LIGHT | Light: all controls | representative 24 MP RAW | cold + warm | off + histogram | requires licensed local RAW |
| RAW24-ADJUST | Adjust: every visible control | representative 24 MP RAW | cold + warm | off + histogram | requires licensed local RAW |
| RAW24-EFFECTS | Effects: every visible control | representative 24 MP RAW | cold + warm | off + histogram | requires licensed local RAW |
| RAW40-60-DEVELOP | Develop: every decoder control | representative 40–60 MP RAW | cold + warm | off + histogram | requires licensed local RAW |
| RAW40-60-LIGHT | Light: all controls | representative 40–60 MP RAW | cold + warm | off + histogram | requires licensed local RAW |
| RAW40-60-ADJUST | Adjust: every visible control | representative 40–60 MP RAW | cold + warm | off + histogram | requires licensed local RAW |
| RAW40-60-EFFECTS | Effects: every visible control | representative 40–60 MP RAW | cold + warm | off + histogram | requires licensed local RAW |

For each completed row, attach the `.trace` from Points of Interest + Metal System Trace and a
value-only summary containing: capture ID, Mac/chip/memory, OS, commit, Release configuration,
source dimensions/format, RAW decoder/version, viewport/backing pixels, requested/effective render
dimensions, cold/warm state, supporting-work state, telemetry summary, and dropped/coalesced values.
Do not substitute the fake renderer's 60 MP-class test for these rows: it is orchestration-only.

## Current checkout record

No camera RAW is shipped in `realworldtest/`, and no logged-in display capture was available during
repository verification. Therefore the RAW rows and hardware latency claims remain explicitly
pending rather than being fabricated from generated PNGs or unit-test timings.
