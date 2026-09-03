---
id: LUMO-145
title: Add removable-camera-media import flow
type: feature
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - import
  - future
  - macos
  - photo-workflow
created: 2026-09-03T01:12:24.531Z
updated: 2026-09-03T01:26:36.000Z
depends_on:
  - LUMO-014
  - LUMO-015
estimate: 13
order: zzy
board: product
---

## Objective

Add a removable-camera-media import flow that detects supported mounted volumes, exposes them in Lumo's import menu, and takes the user directly to image selection.

## Context

Lumo currently supports Open Image, source-folder import, and streamed Photos import; it has no device discovery or image-first volume selector. When an SD card or other supported removable volume is mounted, the app may make the volume discoverable and provide an image-first import flow instead of forcing the user through a generic folder chooser. This is removable-media file import, not camera tethering or device control.

## Acceptance criteria

- [ ] The Import menu has a clear removable-media entry and shows recognizable names only for mounted volumes that contain supported image files; the existing Open Image, source-folder, and Photos entries remain available.
- [ ] Selecting a supported volume opens a custom selector that scans `ImageDecoder.supportedTypes` and shows thumbnails, filenames, orientation, and useful available metadata.
- [ ] The volume flow goes directly to image selection without a second generic folder-selection step.
- [ ] The user can select all/none, cancel safely, and start an explicit copy/import; progress, skipped files, and per-file failures are reported.
- [ ] Imported files use the existing `PhotoAsset`/`ImageCollection` semantics for stable identity, naming, orientation, metadata, duplicate handling, bookmarks, and edit initialization.
- [ ] With no supported removable media mounted, the menu remains understandable and the current folder import flow remains the fallback.
- [ ] Permission denial, volume removal during scan/import, unsupported files, duplicate files, and unreadable media produce recoverable states without deleting or modifying source-media files.
- [ ] Automated coverage uses a media-volume abstraction for discovery, empty state, scan, selection, cancellation, and failure; platform QA covers a real SD card or representative mounted-volume fixture.

## Implementation notes

Define a media-volume abstraction so discovery and scanning are testable without hardware. Use the App Sandbox security-scoped access model and existing bookmark conventions as required. Do not silently copy or delete files from removable media; make the destination and copy behavior explicit.

## Verification

Run the media-volume and selector tests with fixture volumes and failure injection. Complete manual QA on a real SD card or representative mounted-volume fixture, including permission denial and removal during scan/import; verify existing folder and Photos import still work.

## Out of scope

- Camera tethering, live capture, camera control, catalog sync, or vendor-specific camera SDKs.
- Changing the existing image decoder/render pipeline beyond the import adapter needed to feed it.
