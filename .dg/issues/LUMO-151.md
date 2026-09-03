---
id: LUMO-151
title: Create and integrate a product icon
type: feature
status: ready
priority: low
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - icon
  - branding
  - macos
  - design
  - human-in-loop
created: 2026-09-03T01:12:27.938Z
updated: 2026-09-03T01:12:28.219Z
order: zzy
board: product
---

## Objective

Create a polished product icon asset and integrate it into the application so it appears consistently in the app bundle, Finder, Dock, and supported launch surfaces.

## Context

The product currently needs an icon. AI can generate the source SVG and prepare the icon artwork; the platform-specific icon packaging/export step may require Apple tooling or a human-in-the-loop if the local environment cannot run the official icon creator.

## Acceptance criteria

- [ ] A new product icon is designed as an original SVG with clear source dimensions, safe-area guidance, and an appropriate light/dark or system-background treatment.
- [ ] The SVG is reviewed at native and small sizes and remains legible without relying on fine detail or text.
- [ ] The icon is converted into the platform's required app-icon asset format and all required sizes/scales are present, or an explicit human handoff is recorded if the official Apple export tool is unavailable.
- [ ] The application bundle references the new icon and the icon is verified in Finder/Dock or the equivalent supported launch surface.
- [ ] Build/package scripts include the icon source/output so a clean build reproduces the result; no generated-only local file is required.
- [ ] The repository includes attribution/licensing notes for any external inspiration or assets and does not use unlicensed third-party artwork.
- [ ] Automated packaging checks verify the icon asset is present and referenced; manual visual QA covers the installed app icon.

## Implementation notes

Generate and commit the SVG source first. If Apple Icon Creator/Icon Composer requires computer control or an unavailable macOS-only step, stop at the documented human boundary with the SVG, exact export settings, expected output path, and verification checklist ready for completion.
