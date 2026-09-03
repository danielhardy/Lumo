---
id: LUMO-150
title: Bundle a licensed starter library of pre-built LUTs
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - lut
  - looks
  - assets
  - licensing
created: 2026-09-03T01:12:27.350Z
updated: 2026-09-03T01:12:27.663Z
order: zzy
board: product
---

## Objective

Ship a curated set of ready-to-use LUTs for common creative directions, including black and white, cinematic, film-inspired, and Fuji-inspired looks.

## Context

A starter library would make Looks useful immediately and give users examples of what the LUT workflow can do. Only assets with compatible licenses and clear provenance may be bundled; proprietary camera profiles or ripped commercial film emulations must not be presented as official profiles.

## Acceptance criteria

- [ ] The app ships a curated starter set of valid LUT files in documented categories: black and white, cinematic, film-inspired, and Fuji-inspired or analogous color profiles.
- [ ] Every bundled asset has recorded source, author, license, attribution requirements, and any redistribution constraints in a machine-readable manifest and user-visible acknowledgements where required.
- [ ] The UI groups the starter LUTs by category, shows usable names and previews, and distinguishes bundled LUTs from user-created LUTs.
- [ ] Applying each bundled LUT succeeds on representative supported images without corrupting the source or edit history.
- [ ] Invalid, missing, or incompatible bundled assets fail gracefully and do not prevent the rest of the Looks library from loading.
- [ ] The package/build process verifies that every manifest entry points to an included valid LUT and rejects unlicensed or missing assets.
- [ ] Automated coverage verifies manifest validation, loading, category display, previews, application, and graceful partial failure.

## Implementation notes

Prefer genuinely redistributable open-source assets or create original in-house assets. Use descriptive “film-inspired” names unless a license explicitly permits a trademarked stock/profile name; do not imply endorsement by Fuji or any film manufacturer. Coordinate the asset directory and discovery rules with the Settings and Save as LUT tickets.
