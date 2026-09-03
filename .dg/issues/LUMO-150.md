---
id: LUMO-150
title: Bundle a small, licensed starter library of Looks
type: feature
status: done
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
updated: 2026-09-03T05:05:24.614Z
depends_on:
  - LUMO-042
  - LUMO-146
estimate: 8
order: a0
board: product
commits:
  - c1cb5378666ba17367b0b1cfbec5d2da030d4803
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings:
    - "performance (minor, fixed): LookPreviewSwatch.colors materialized the entire CubeLUT float table (CubeLUT.tableFloats, up to ~4.4 MB for a 65^3 LUT) on every SwiftUI render of a Look row, for both bundled and user-imported Looks. Fixed in a localized commit on the current branch: added CubeLUT.previewSamples(count:) which reads only the needed RGB samples directly from the backing Data, and switched LookPreviewSwatch to use it."
  fixes: []
  verification_commits:
    - c1cb5378666ba17367b0b1cfbec5d2da030d4803
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-03T05:05:24.611Z
  session: 01MTL208F6K58677MN
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


### Comment — codex @ 2026-09-03T04:57:29.959Z

Implemented bundled starter Looks: four original MIT-licensed 3³ .cube assets, manifest-backed provenance/approval/acknowledgement, strict Package.swift and runtime validation, read-only starter/user source separation in the inspector, previews, graceful partial failure, and automated coverage. Checks: swift build -c release; swift test (692 passed, 14 skipped); git diff --check; dg validate.

## Agent log

- 2026-09-03T05:05:24.613Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- performance (minor, fixed): LookPreviewSwatch.colors materialized the entire CubeLUT float table (CubeLUT.tableFloats, up to ~4.4 MB for a 65^3 LUT) on every SwiftUI render of a Look row, for both bundled and user-imported Looks. Fixed in a localized commit on the current branch: added CubeLUT.previewSamples(count:) which reads only the needed RGB samples directly from the backing Data, and switched LookPreviewSwatch to use it.
Fixes:
- None
Verification commits:
- c1cb5378666ba17367b0b1cfbec5d2da030d4803
Actor: claude
Resolved model: sonnet
Pickup session: 01MTL208F6K58677MN
Summary: Independent verification passed: bundled starter Looks meet all acceptance criteria (provenance/manifest gate, read-only category separation, graceful partial failure, full test coverage). Applied one localized perf fix (CubeLUT.previewSamples) to avoid copying the full LUT table on every Look-row render.
