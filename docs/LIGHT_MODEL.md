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
`EditDocument.currentVersion` remains 1. `RenderPipeline.cacheVersion` is 2 because the graph now
has an explicit Light stage and the document hash includes its state.

The current renderer maps Exposure, Contrast, Highlights, and Shadows onto the existing Core Image
nodes. Whites, Blacks, and the master curve are persisted but wait for their dedicated GPU stages;
they are not approximated with an unrelated operation. Neutral Light produces no nodes and is an
exact render identity.
