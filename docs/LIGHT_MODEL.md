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
`EditDocument.currentVersion` remains 1. `RenderPipeline.cacheVersion` is 7: v2 introduced the
explicit Light stage, v3 recorded the refined non-neutral mapping, v4 clamps the curve's interior
points to stay monotonic, v5 adds the GPU-backed Whites and Blacks endpoint stages, and v6 adds the
editable master RGB curve, and v7 adds the global Color stage (see [COLOR_MODEL.md](COLOR_MODEL.md)).

The current renderer applies Exposure with `CIExposureAdjust` in EV and combines Contrast,
Highlights, and Shadows in one five-point `CIToneCurve` GPU stage. The curve keeps its endpoints
fixed, increases separation around the middle for Contrast, and tapers each local control toward its
opposite tonal region. Interior points are clamped to be non-decreasing before being handed to
`CIToneCurve`: some combinations (e.g. strongly negative Contrast with positive Shadows and negative
Highlights) would otherwise push a lower-tone point above a higher-tone one, which the filter renders
as a local tone inversion rather than a smooth curve. Whites then runs as a separate high-end
`CIToneCurve`, followed by the editable master RGB curve and then Whites and Blacks as separate
endpoint `CIToneCurve` stages. The master curve stores normalized ordered control points and uses
piecewise-linear interpolation sampled into a 64³ `CIColorCube`; this is GPU-backed and cannot
overshoot between monotonic points. Whites and Blacks each change its endpoint and
nearest quarter-tone with a smooth rolloff while leaving the opposite half of the range effectively
unchanged. Strong positive Whites and negative Blacks may produce out-of-range values in the lazy
graph, which are finite and clip only when rasterized. Neutral Light produces no nodes and is an
exact render identity.
