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

Imported files retain their canonical file path as the stable `LUTID`. The selected file is
persisted through a security-scoped bookmark, and `LUTLibrary.refresh()` re-reads its bytes before
asking the renderer to invalidate its cached GPU filter. Replacing a file in place therefore cannot
leave the old cube applied after refresh.
