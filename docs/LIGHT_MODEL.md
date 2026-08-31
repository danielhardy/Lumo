# Light model

`LightAdjustments` is the photographer-facing value model for the global Light panel. It is
`Codable`, `Equatable`, and `Sendable`; every scalar is finite and clamped at construction, mutation,
and decode time.

| Control | Neutral | Range | Stored unit |
| --- | ---: | ---: | --- |
| Exposure | 0 | -5...+5 | EV |
| Contrast | 0 | -100...+100 | photographic scale |
| Highlights | 0 | -100...+100 | photographic scale |
| Shadows | 0 | -100...+100 | photographic scale |
| Whites | 0 | -100...+100 | photographic scale |
| Blacks | 0 | -100...+100 | photographic scale |
| Tone curve | diagonal | normalized 0...1 points | master RGB |

The render order is:

```text
RAW develop → Light → Color → legacy ordered adjustments → LUT
```

The inherited adjustment array remains untouched. A v1 document with no `light` key decodes with
neutral Light and therefore retains its old exposure, contrast, highlight, and shadow nodes,
including their original order and Core Image parameter values. This is an additive migration, so
`EditDocument.currentVersion` remains 1. `RenderPipeline.cacheVersion` is 10: v2 introduced the
explicit Light stage, v3 recorded the refined non-neutral mapping, v4 clamps the curve's interior
points to stay monotonic, v5 adds the GPU-backed Whites and Blacks endpoint stages, and v6 adds the
editable master RGB curve, v7 adds the global Color stage, and v10 replaces the master-curve cube
with a reusable 1D Core Image kernel resource (see [COLOR_MODEL.md](COLOR_MODEL.md)).

The current renderer applies Exposure with `CIExposureAdjust` in EV and combines Contrast,
Highlights, and Shadows in one five-point `CIToneCurve` GPU stage. The curve keeps its endpoints
fixed, increases separation around the middle for Contrast, and tapers each local control toward its
opposite tonal region. Interior points are clamped to be non-decreasing before being handed to
`CIToneCurve`: some combinations (e.g. strongly negative Contrast with positive Shadows and negative
Highlights) would otherwise push a lower-tone point above a higher-tone one, which the filter renders
as a local tone inversion rather than a smooth curve. Whites then runs as a separate high-end
`CIToneCurve`, followed by the editable master RGB curve and then Whites and Blacks as separate
endpoint `CIToneCurve` stages. The master curve stores normalized ordered control points and uses
piecewise-linear interpolation sampled into a 256×1 RGBA float texture consumed by a Core Image
kernel; this is GPU-backed and cannot overshoot between monotonic points. The texture and compiled
kernel are actor-confined and reused across renders, so a curve drag updates about 4 KiB rather than
constructing/uploading a 4 MiB 64³ cube. Whites and Blacks each change its endpoint and
nearest quarter-tone with a smooth rolloff while leaving the opposite half of the range effectively
unchanged. Strong positive Whites and negative Blacks may produce out-of-range values in the lazy
graph, which are finite and clip only when rasterized. Neutral Light produces no nodes and is an
exact render identity.

### Tone-curve replacement measurement

The before/after claim is covered by the opt-in `PreviewCostBenchmark` test. It reconstructs the
pre-LUMO-071 `CIColorCube` path from `c459816^`, drives 30 changing curve values, and forces a
1024×768 Core Image rasterization for each tick. Run it with:

```text
LUMO_BENCH=1 swift test --filter PreviewCostBenchmark.testMeasureToneCurveDragCost
```

Captured on 2026-08-31 (macOS arm64e, this checkout):

| path | table payload allocated/uploaded per tick | measured graph + GPU render time |
|---|---:|---:|
| before: 64³ RGBA Float32 cube | 4,194,304 bytes | 85.40 ms/tick |
| after: cached 256×1 RGBA Float32 texture | 4,096 bytes | 3.31 ms/tick |

That run measured a 1,024× payload reduction and 25.8× lower per-tick time. The byte figures are
the actual `Data` payloads handed to Core Image, not estimates from the comments; the timing includes
curve-table construction, Core Image graph construction, and forced GPU rasterization. The benchmark
is gated by `LUMO_BENCH` because the baseline intentionally allocates a 4 MiB cube per sample.
