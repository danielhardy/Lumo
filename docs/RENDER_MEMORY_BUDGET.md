# Render intermediate memory budget

`RenderEngine` only materializes an intermediate when its estimated working set fits the
corresponding bounded cache. The estimate is made before allocation and uses the actual
`RGBA16Float`/`RGBAh` footprint:

```text
CPU working set = width × height × 8 bytes
GPU working set = width × height × 8 bytes
admission cost  = CPU working set + GPU working set
```

The CPU term covers the `Data` backing a completed Core Image prefix. The GPU term reserves the
same-size half-float texture that Core Image may retain or create when the prefix is consumed by a
Metal-backed downstream render. Arithmetic saturates on overflow. The developed-source and
processing-prefix cache budgets are therefore working-set budgets, not merely post-hoc eviction
costs.

When a prefix is above budget, `RenderEngine` skips the bitmap allocation and continues with the
original lazy graph. The processing-prefix caller fuses that graph with the downstream LUT/crop/
vignette/grain stages; the RAW session returns its request-local lazy output without retaining it
across a mutable-filter edit. Settled RAW development follows the same rule and does not admit a
lazy decoder graph after its completed form is rejected. This explicitly non-cached path preserves
the normal render graph and pixel parity while avoiding a rejected full-frame allocation on every
edit.

Small prefixes still use the completed-image cache, so downstream-only edits can reuse their
materialized result. Memory-pressure events continue to evict all retained render resources.
