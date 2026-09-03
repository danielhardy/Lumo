---
id: LUMO-145
title: Add smart Import from Camera and SD-card media flow
type: feature
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - import
  - camera
  - sd-card
  - macos
  - photo-workflow
created: 2026-09-03T01:12:24.531Z
updated: 2026-09-03T01:12:24.800Z
order: zzy
board: product
---

## Objective

Add an Import from Camera workflow that detects removable camera media, suggests it in the import menu, and takes the user directly to image selection.

## Context

Import from Camera is currently missing. When an SD card or other supported removable volume is mounted, the app should make the device discoverable in the import dropdown and provide a Lightroom-like image-first import flow instead of forcing the user through an unnecessary folder selection step.

## Acceptance criteria

- [ ] The import menu includes an Import from Camera entry and, when supported removable media is mounted, shows a recognizable device/volume name.
- [ ] Selecting a detected camera volume opens a custom import selector that scans supported image files and shows thumbnails, filenames, orientation, and enough metadata to make selection useful.
- [ ] The camera-volume flow goes directly to image selection without first asking the user to choose a folder.
- [ ] The user can select images, select all/none, cancel safely, and start the import; progress, skipped files, and failures are reported.
- [ ] Imported files preserve the existing import semantics for naming, metadata, orientation, duplicates, and edit initialization.
- [ ] If no supported camera media is mounted, the menu remains understandable and the existing folder import flow remains available.
- [ ] Permission denial, volume removal during scan/import, unsupported files, duplicate files, and unreadable media produce recoverable states.
- [ ] Automated coverage exercises device discovery/empty state, selector behavior, cancellation, and import failure; platform-specific manual QA covers a real SD card or representative mounted-volume fixture.

## Implementation notes

Define a media-volume abstraction so discovery and scanning are testable without hardware. On macOS, use the platform's security-scoped access/entitlement model as required by the app's sandbox. Do not silently copy or delete files from removable media; make the destination and copy behavior explicit.
