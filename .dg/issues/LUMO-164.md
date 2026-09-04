---
id: LUMO-164
title: "Audit: make export location metadata privacy explicit"
type: bug
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - security
  - privacy
  - export
  - audit
created: 2026-09-03T23:28:45.962Z
updated: 2026-09-03T23:28:45.962Z
order: zzz
board: product
---

## Objective

Make export handling of GPS/location metadata explicit and safe for users sharing images.

## Context

`ExportOptions` defaults to metadata preservation, and the renderer copies EXIF/TIFF/GPS dictionaries. The export UI currently exposes no metadata or location control, so a photo can silently retain precise location data when exported or delivered to Photos.

## Acceptance criteria

- [ ] The export surface exposes a clear control for preserving camera metadata and separately for including location metadata.
- [ ] The default behavior is documented and reflects a deliberate privacy choice.
- [ ] JPEG, TIFF, and PNG exports honor the chosen location policy for both URL- and Data-backed sources.
- [ ] Regression tests verify GPS is stripped when requested and preserved only when explicitly allowed.
- [ ] The choice is visible before Photos delivery and file export, not only in a hidden advanced path.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
