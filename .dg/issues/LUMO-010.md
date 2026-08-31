---
id: LUMO-010
title: Copy and paste edits to one or many photos
type: task
status: done
priority: high
labels:
  - mvp
  - epic:domain
  - phase:1
created: 2026-08-30T18:30:20.477Z
updated: 2026-08-31T03:58:37.477Z
depends_on:
  - LUMO-007
  - LUMO-009
estimate: 5
order: a0
board: product
commits:
  - "256e922"
---

## Objective

Support a photographer's core edit-transfer workflow with a structure that can later expose selective copy.

## Context

Part of **Epic 1 — Durable per-photo edit domain**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define an edit clipboard payload with separable Light, Color, Effects, Crop, LUT, and develop policy.
- Ship Copy All Edits and Paste Edits.
- Apply paste to the active photo or current multi-selection as one operation per destination.
- Make paste undoable and persist the results.

## Acceptance criteria

- [ ] All edits copy between compatible photos without transferring source-specific RAW defaults accidentally.
- [ ] Multi-select paste updates every selected destination and no others.
- [ ] Each destination can undo the paste.
- [ ] Clipboard structure supports future category selection without schema replacement.

## Verification

- Add RAW-to-RAW, RAW-to-JPEG, single, multi-select, and undo tests.

## Out of scope

- Selective-copy checkbox UI.
- Presets marketplace.

### Comment — codex @ 2026-08-31T03:58:25.292Z

Implemented in commit 256e922. Added versioned EditClipboardPayload with separate Light, Color, Effects, Crop, LUT, and develop policy fields; Copy All Edits and Paste Edits commands/UI; macOS command-click multi-selection; per-destination paste into in-session PhotoEditSession state with one undo snapshot each. RAW explicit develop values copy only to RAW destinations, preserving JPEG destination defaults. Added Codable/schema, RAW-to-RAW/RAW-to-JPEG, single-paste, multi-selection, isolation, and undo tests. Verification: swift test passed (325 executed, 20 skipped, 0 failures); swift build -c release passed; dg validate passed with pre-existing warnings only.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T03:58:37.475Z: Copy/paste edits shipped with category-separated clipboard payload, RAW-safe develop policy, command-click multi-selection, per-destination undo, and in-session edit persistence. Full tests and release build pass.
