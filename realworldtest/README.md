# Real-world test photos

Camera RAW files are intentionally not stored in this repository. They are large, carry embedded
metadata, and may include people, locations, or other material whose redistribution rights are not
covered by the source photographer's license. This directory is only the documentation anchor for
local opt-in fixtures.

To run the slow RAW regression lane, point it at a directory containing a license-cleared RAW and,
for derive tests, a same-stem in-camera JPG pair:

```bash
LUMO_RAW_FIXTURE_DIR=/absolute/path/to/fixtures \
swift test --filter '(RAW|DeriveInvariance|ImageLoadingTests/testLoadingARAW|RenderPipelineTests/testRAW|PreviewCutoverTests/testRAW)'
```

Do not commit those files or add them to Git LFS without an approved remote storage, retention, and
access policy. The normal test lane uses generated fixtures and remains fully runnable without them.

The following terms apply to files Daniel Hardy has separately released for local project use:

I, Daniel Hardy, license the photo files in this directory under the
[Creative Commons Attribution 4.0 International License (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

You may share and adapt these files for any purpose, including commercial purposes, provided that
you give appropriate credit, link to the license, and indicate whether changes were made. Suggested
credit: “Photo by Daniel Hardy, used under CC BY 4.0.”

This release covers my copyright in the contributed photographs. It does not grant rights to any
third-party people, property, trademarks, or other material depicted in them; users are responsible
for obtaining any permissions those uses may require. The files are provided as-is, without warranty.
