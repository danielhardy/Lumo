---
id: LUMO-146
title: Create a Settings section for appearance, import/export folders, and LUT storage
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - settings
  - preferences
  - dark-mode
  - import
  - export
  - lut
created: 2026-09-03T01:12:25.086Z
updated: 2026-09-03T01:12:25.364Z
order: zzy
board: product
---

## Objective

Create a persistent Settings section that exposes the app's appearance preference, default import/export folders, and canonical LUT storage location.

## Context

Users need a discoverable place to control recurring workflow preferences. The settings must survive relaunch, handle unavailable folders, and clearly explain which values affect future imports/exports versus existing files.

## Acceptance criteria

- [ ] A discoverable Settings section is available from the app's primary navigation/menu and follows existing navigation, focus, and accessibility conventions.
- [ ] Appearance includes an “Always dark mode” option that persists across relaunch and overrides the system appearance when enabled; the setting can be turned off to restore the documented behavior.
- [ ] Users can choose, view, reset, and test the default import folder and default export folder; future operations use those defaults without changing existing files.
- [ ] The UI handles a missing, disconnected, or inaccessible configured folder with a clear recovery action and a safe fallback.
- [ ] Settings identifies where user LUTs are stored, provides a way to reveal/open that location when supported, and documents whether bundled and user-created LUTs are separate.
- [ ] Preference reads/writes are versioned or migration-safe and do not lose unrelated settings during an upgrade.
- [ ] Automated coverage verifies persistence, dark-mode precedence, folder selection/reset/unavailability, LUT-location display, and accessibility labels.

## Implementation notes

Use the platform's secure folder bookmark/access mechanism where required. Establish one canonical LUT directory in this ticket and make the path available to the LUT browser/save flow. Avoid exposing raw implementation paths without a human-readable label.
