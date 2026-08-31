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

## HSL mixer

`ColorMixerAdjustments` contains eight explicit `ColorMixerChannel` values: Red, Orange, Yellow,
Green, Aqua, Blue, Purple, and Magenta. Each channel stores Hue, Saturation, and Luminance on a
finite, clamped `-100...+100` photographer-facing range. The value is nested in
`ColorAdjustments`, so it participates automatically in `EditDocument` Codable persistence,
`editHash`, equality, per-photo undo/redo snapshots, and the existing document copy boundary.
Missing mixer or channel keys decode as neutral for additive migration.

The renderer applies all eight channels in one Core Image `CIColorKernel`. Each fixed hue center
uses a raised-cosine 45° support window; neighboring windows overlap smoothly and circular hue
distance makes Red continuous across 0°/360°. The kernel computes HSL and combines the weighted
Hue, Saturation, and Luminance deltas without Swift CPU pixel iteration. Hue endpoints move by
±30°, Saturation by ±1 HSL saturation, and Luminance by ±0.5 HSL lightness. Neutral mixer state
returns the original `CIImage` exactly, and preview/export share this same graph and working-space
output boundary.

## Three-way color grading

`ColorGradingAdjustments` adds Shadows, Midtones, and Highlights wheels, each with a hue in
degrees and a 0...100 saturation. `Blending` is 0...100 (narrow to broad overlap) and `Balance` is
-100...+100 (shadow to highlight bias). A wheel hue without saturation is intentionally an exact
identity, so hue positions can be persisted independently of whether a wheel is active. Missing
grading state decodes as neutral for additive document migration.

The renderer applies all three wheels in one Core Image color kernel after the HSL mixer and before
the ordered effects and LUT. It computes luminance-weighted smooth tonal partitions, shifts the
partition center for Balance, and brings the boundaries together for Blending before normalizing
the overlap. The GPU path preserves alpha, handles neutral grayscale pixels, and uses no Swift
per-pixel loop. Pipeline cache version 9 records the new stage order for reproducible renders.
