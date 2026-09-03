---
id: LUMO-151
title: Create and integrate Lumo's product icon
type: feature
status: ready
priority: low
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - release
  - icon
  - branding
  - macos
  - design
  - human-in-loop
created: 2026-09-03T01:12:27.938Z
updated: 2026-09-03T01:26:36.000Z
estimate: 5
order: zzy
board: product
---

## Objective

Create a polished Lumo product icon source and integrate it into the existing macOS asset catalog so it appears consistently in the app bundle, Finder, Dock, and supported launch surfaces.

## Context

The repository has an `AppIcon.appiconset` catalog with slot metadata but no image files, and the README already identifies the icon as a release-preparation gap. The icon should be original, legible at macOS sizes, and reproducible from repository inputs. Source artwork may be SVG, but the actual asset-catalog outputs must be produced with the available Apple tooling or handed off explicitly when that tooling is unavailable.

## Acceptance criteria

- [ ] An original Lumo icon source is added with documented source dimensions, safe-area guidance, and treatment against macOS light/dark/system backgrounds.
- [ ] The artwork is reviewed at native and small sizes and remains legible without relying on fine detail or text.
- [ ] The existing `Sources/Lumo/Assets.xcassets/AppIcon.appiconset` contains all required macOS sizes/scales with valid image references, or an explicit human handoff records the exact remaining Apple export step.
- [ ] The generated app bundle references the new icon and manual QA verifies it in Finder, Dock, and a launched Lumo window where available.
- [ ] Source artwork and catalog outputs are included in the repository/build inputs so a clean Xcode archive reproduces the result; no generated-only local file is required.
- [ ] Attribution/licensing notes cover any external inspiration or assets, and no unlicensed third-party artwork is used.
- [ ] Automated packaging checks verify that every AppIcon catalog slot is present, references an existing valid image, and is the icon used by the application target.

## Implementation notes

Generate and commit the source artwork first. If Apple Icon Composer or another required macOS-only step is unavailable, stop at the documented human boundary with the source, exact export settings, expected output paths, and verification checklist ready for completion. Keep this ticket limited to the product icon; do not change unrelated app branding or bundle identifiers.

## Verification

Run asset-catalog/package checks and a clean Xcode archive. Manually inspect native and small-size rendering, then verify the installed icon in Finder, Dock, and the launched app; record the exact human handoff if Apple export tooling is unavailable.

## Out of scope

- App Store marketing artwork, launch screens, document icons, or a bundle-identifier/signing migration.
