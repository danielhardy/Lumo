# Effects model

`EditDocument.effects` stores Texture, Clarity, and Dehaze on the photographer-facing `-100…100`
scale. Zero is the exact identity for all three controls; values are finite and clamped when the
model is constructed or decoded. The field is an additive Codable migration, so documents written
before Effects was introduced decode with neutral Effects.

The shared graph applies Effects after Light and Color, before the legacy ordered adjustments and
the LUT. Texture uses a small-radius luminance detail/softening operation. Clarity uses a broader
operation weighted toward midtones. Dehaze combines a broader local operation with restrained
contrast, saturation, and tone-curve changes. All spatial radii are fractions of the current image's
shortest side, after the preview source downscale, so preview and export preserve the same relative
photographic scale.

The render cache version is 11 because adding the stage changes pixels for an unchanged document
shape only when the new field is non-neutral; old documents remain neutral and preserve their look.
