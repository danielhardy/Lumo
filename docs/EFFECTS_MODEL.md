# Effects model

`EditDocument.effects` stores Texture, Clarity, and Dehaze on the photographer-facing `-100…100`
scale, plus a nested post-crop Vignette model. Zero is the exact identity for the three detail
controls and Vignette Amount; all values are finite and clamped when the model is constructed or
decoded. The field is an additive Codable migration, so documents written before Effects was
introduced decode with neutral Effects.

The shared graph applies Texture, Clarity, and Dehaze after Light and Color, before the legacy
ordered adjustment array and LUT. Vignette runs after the LUT, over the current image extent; this
is the post-crop/output geometry even before a persisted crop model exists. Its normalized elliptical
mask uses Amount (`-100…100`), Midpoint (`0…100`, neutral 50), Roundness (`-100…100`, neutral 0),
Feather (`0…100`, neutral 50), and Highlights (`0…100`, neutral 0). Highlights attenuates the mask
over bright pixels so edge detail is retained. The stage is GPU-backed and clips back to its input
extent, so it cannot change output dimensions. All spatial radii are fractions of the current image's
shortest side, after the preview source downscale, so preview and export preserve the same relative
photographic scale.

The render cache version is 12 because adding the post-LUT vignette stage changes pixels for an
unchanged document shape only when the new field is non-neutral; old documents remain neutral and
preserve their look.
