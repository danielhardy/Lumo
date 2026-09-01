# Effects model

`EditDocument.effects` stores Texture, Clarity, and Dehaze on the photographer-facing `-100…100`
scale, plus nested post-crop Vignette and Grain models. Zero is the exact identity for the three
detail controls and Vignette/Grain Amount; all values are finite and clamped when the model is
constructed or decoded. The field is an additive Codable migration, so documents written before
Effects was introduced decode with neutral Effects.

The shared graph applies Texture, Clarity, and Dehaze after Light and Color, before the legacy
ordered adjustment array and LUT. Vignette and Grain run after the LUT, over the current image
extent; this is the post-crop/output geometry even before a persisted crop model exists. Vignette's
normalized elliptical mask uses Amount (`-100…100`), Midpoint (`0…100`, neutral 50), Roundness
(`-100…100`, neutral 0), Feather (`0…100`, neutral 50), and Highlights (`0…100`, neutral 0).
Highlights attenuates the mask over bright pixels so edge detail is retained.

Grain uses Amount (`0…100`, neutral 0), Size (`0…100`, neutral 50), and Roughness (`0…100`,
neutral 50). Amount is the identity gate; the other values are retained while Amount is zero.
The GPU noise field is seeded from the source fingerprint and a versioned pipeline constant, not
from the frame, document, or slider values. The same source therefore keeps its grain field while
unrelated edits and grain sliders change. The field combines correlated noise octaves and restrained
chroma variation so it reads as photographic texture rather than independent per-channel noise.

The stage is GPU-backed and clips back to its input extent, so it cannot change output dimensions.
All spatial radii and grain frequency are relative to the current image's shortest side, after the
preview source downscale. Size maps to 48–192 grain cells per shortest output side (larger Size means
larger cells), so a preview and a full-resolution export preserve the same relative photographic
scale when viewed at their respective output sizes.

The render cache version is 13 because adding the post-LUT grain stage changes pixels for an
unchanged document shape only when the new field is non-neutral; old documents remain neutral and
preserve their look. Grain is part of `EditDocument.effects`, so preview cache keys include all
three grain parameters through the document hash; no random frame output is cached.
