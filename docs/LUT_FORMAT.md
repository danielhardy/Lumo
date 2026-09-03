# LUT file support

Lumo's Look stage accepts text-based `.cube` files and text-based `.look` files whose contents use
the same 3D cube grammar. A `.look` extension is accepted for interoperability with tools that use
that suffix for a plain cube export; proprietary binary or XML Adobe `.look` packages are rejected
with an import error rather than guessed at.

Supported input:

- A 3D table declared by `LUT_3D_SIZE`, with 2…65 samples per axis. Common 17³, 33³, and 65³
  exports are supported.
- `TITLE`, `DOMAIN_MIN`, and `DOMAIN_MAX`, plus comments and other non-numeric vendor metadata.
  Spaces, tabs, UTF-8 BOMs, CRLF endings, and trailing `#` comments are accepted.
- The common vendor spelling `LUT_3D_INPUT_RANGE min max`, interpreted as the same range on all
  three channels.
- Output values outside 0…1, which Core Image can represent and which are valid in the cube
  interchange format.

The parser deliberately rejects 1D cubes, mixed 1D/3D tables, reversed domains, non-finite
numbers, malformed rows, missing/truncated tables, and dimensions outside 2…65. Lumo's renderer
uses Core Image's GPU-backed `CIColorCubeWithColorSpace`, so 1D files need to be converted to a 3D
cube by the authoring tool before import.

## Save as Look/LUT

The active editor can save the LUT-compatible portion of its `EditDocument` through a versioned
support matrix (currently v1). The default export is a 33³ cube in the current working color space
(currently sRGB), with `DOMAIN_MIN 0 0 0` and `DOMAIN_MAX 1 1 1`. The file comments record the cube
size, working space, support-matrix version, measured conversion tolerance, included stages, and
omitted stages.

Verified global stages include Light/tone, Color/mixer/grading, ordered per-pixel adjustment nodes,
and a resolved existing 3D Look. RAW development, crop/rotation, masking, Texture, Clarity,
Dehaze, vignette, grain, and other spatial or source-dependent stages are omitted. The confirmation
sheet lists each omission before the file is written; the saved cube does not claim to reproduce
those edits. Export verification measures the generated cube against the same global render graph at
off-lattice RGB probes and requires a maximum absolute channel error of 0.03 at the default 33³
resolution.

Imported files retain their canonical file path as the stable `LUTID`. The selected file is
persisted through a security-scoped bookmark, and `LUTLibrary.refresh()` re-reads its bytes before
asking the renderer to invalidate its cached GPU filter. Replacing a file in place therefore cannot
leave the old cube applied after refresh.

## User Look storage

Lumo's canonical user Look/LUT folder is `~/Library/Application Support/Lumo/Looks` (the path is
resolved with the user's Application Support directory at runtime). User-created and imported Looks
are kept distinct from any future bundled assets. The Settings window can reveal this folder, and
the derive and Save as Look flows use it when no external Look folder has been selected.
