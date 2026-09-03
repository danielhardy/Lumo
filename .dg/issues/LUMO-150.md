---
id: LUMO-150
title: Bundle a small, licensed starter library of Looks
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
  - ux
created: 2026-09-03T01:12:27.350Z
updated: 2026-09-03T01:26:36.000Z
depends_on:
  - LUMO-042
  - LUMO-146
estimate: 8
order: zzy
board: product
---

## Objective

Ship a small curated set of ready-to-use Looks for common creative directions, using only original or clearly redistributable `.cube` assets.

## Context

A starter library would make Lumo's existing Look inspector useful immediately and give users examples of what the LUT workflow can do. Lumo currently discovers user/imported files through `LUTLibrary`; bundled assets need a separate, read-only source and clear visual distinction. Only original or compatible redistributable assets with recorded provenance may ship. Proprietary camera profiles and ripped commercial film emulations must not be presented as official profiles. Avoid manufacturer trademarks in category or asset names unless rights are explicit; “warm slide-inspired” is sufficient for the intended direction.

## Acceptance criteria

- [ ] The app ships a deliberately small starter set of valid `.cube` Looks in documented categories such as Monochrome, Cinematic, Film-inspired, and Warm slide-inspired; names do not imply manufacturer endorsement.
- [ ] Every bundled asset has source/author, license, attribution requirements, redistribution constraints, and an internal approval record in a machine-readable manifest; required user-visible acknowledgements are included.
- [ ] The Look inspector groups starter Looks by category, shows usable names/previews, and distinguishes bundled read-only Looks from user-imported or saved Looks.
- [ ] Applying each bundled Look succeeds on representative supported standard and RAW-rendered images without corrupting the source or edit history.
- [ ] Invalid, missing, or incompatible bundled assets fail gracefully and do not prevent the rest of the Look library from loading.
- [ ] The package/build process validates that every manifest entry points to an included valid LUT and fails closed for missing provenance, unlicensed, or malformed assets.
- [ ] Automated coverage verifies manifest/provenance validation, loading, category display, previews, application, and graceful partial failure.

## Implementation notes

Prefer original in-house assets or genuinely redistributable assets with licenses compatible with Lumo's distribution. Use descriptive names such as “Warm Slide” rather than a trademarked stock/profile name; do not imply endorsement by Fuji or any film manufacturer. Keep bundled assets in a package-owned resource directory and coordinate the discovery/source rules with LUMO-146 and LUMO-147.

## Verification

Run manifest/build validation and Look-library tests in a clean checkout, including malformed/missing partial-library cases. Manually review every bundled Look on representative standard and RAW-rendered images and verify attribution/acknowledgements before distribution.

## Out of scope

- Downloading assets at runtime, bundling proprietary camera profiles, or reproducing commercial film emulations.
- Editing user LUT files in place or changing the existing external Look import semantics.
