---
id: LUMO-078
title: "LUMO-075 follow-up: main-preview NSImage fallback path is dead in production — remove or re-scope"
type: task
status: done
priority: low
labels:
  - verification
created: 2026-09-01T02:07:16.257Z
updated: 2026-09-01T05:22:19.312Z
depends_on:
  - LUMO-075
order: n
board: product
commits:
  - 59013b0
---

## Objective

LUMO-075 follow-up: main-preview NSImage fallback path is dead in production — remove or re-scope

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-01T05:22:15.845Z

Implemented and verified via the existing LUMO-077 change in commit 59013b0: removed previewNSImage/originalPreviewNSImage state and PreviewView fallback branches, while retaining the raster compatibility seam by presenting CGImage results through PreviewSurface. No legacy references remain in Sources or Tests. Verification: swift test (462 passed, 25 expected skips), swift build -c release, git diff --check, dg validate OK aside from the pre-existing runner-model warning.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T05:22:19.311Z: Completed by the existing LUMO-077 implementation in 59013b0. The dead main-preview NSImage fallback and AppViewModel state were removed; PreviewSurface is now the sole display path, with the raster compatibility seam converted into CIImage presentation. Full tests and release build pass.
