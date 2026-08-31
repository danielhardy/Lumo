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
RAW develop → Light → legacy ordered adjustments → LUT
```

The inherited adjustment array remains untouched. A v1 document with no `light` key decodes with
neutral Light and therefore retains its old exposure, contrast, highlight, and shadow nodes,
including their original order and Core Image parameter values. This is an additive migration, so
`EditDocument.currentVersion` remains 1. `RenderPipeline.cacheVersion` is 4: v2 introduced the
explicit Light stage, v3 recorded the refined non-neutral mapping, and v4 clamps the curve's
interior points to stay monotonic (see below).

The current renderer applies Exposure with `CIExposureAdjust` in EV and combines Contrast,
Highlights, and Shadows in one five-point `CIToneCurve` GPU stage. The curve keeps its endpoints
fixed, increases separation around the middle for Contrast, and tapers each local control toward its
opposite tonal region. Interior points are clamped to be non-decreasing before being handed to
`CIToneCurve`: some combinations (e.g. strongly negative Contrast with positive Shadows and negative
Highlights) would otherwise push a lower-tone point above a higher-tone one, which the filter renders
as a local tone inversion rather than a smooth curve. Whites, Blacks, and the master curve are
persisted but wait for their dedicated GPU stages; they are not approximated with an unrelated
operation. Neutral Light produces no nodes and is an exact render identity.
