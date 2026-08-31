# Color model

`ColorAdjustments` stores the global Vibrance and Saturation controls on the edit document. The
persisted/UI values use the photographer-facing `-100...+100` scale; the renderer converts them
once at the Core Image boundary:

| Control | Neutral | UI range | Core Image value |
| --- | ---: | ---: | --- |
| Vibrance | 0 | -100...+100 | `CIVibrance.inputAmount = value / 100` |
| Saturation | 0 | -100...+100 | `CIColorControls.inputSaturation = 1 + value / 100` |

Vibrance is applied before Saturation. `CIVibrance` increases chroma preferentially in less
saturated pixels, so skin and already-colourful foliage/primaries do not receive the same boost as
they would from a uniform saturation multiplier. Saturation remains the predictable global control:
`-100` maps to zero saturation (luminance-only output), `0` is the exact no-op, and `+100` is 2×.

Both stages are Core Image nodes; no Swift per-pixel loop is used. Core Image preserves alpha and
the input colour metadata. The render engine writes the final raster in the request's
`WorkingSpace`, which is the gamut boundary shared by preview and export. Out-of-gamut values from
positive saturation/vibrance are left in the lazy graph and clipped by the requested output format,
while all model inputs and normalized filter parameters are finite and bounded.
