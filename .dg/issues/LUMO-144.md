---
id: LUMO-144
title: Polish the Look inspector empty state and add-look action
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ux
  - looks
  - accessibility
  - design-system
created: 2026-09-03T01:12:24.018Z
updated: 2026-09-03T01:26:36.000Z
depends_on:
  - LUMO-085
  - LUMO-090
estimate: 3
order: zzy
board: product
---

## Objective

Make Lumo's Look inspector feel polished and inviting when empty, with a prominent full-width action for importing the first Look.

## Context

The current `LookInspectorView` already owns the empty state and the “Import Look” action. The empty state should use Lumo's existing inspector, accordion, and theme primitives, and should make the real workflow—choosing an external `.cube`/`.look` file or Look folder—clear without implying that Lumo ships a starter library. Keep the redesign deliberate and calm rather than adding decorative complexity.

## Acceptance criteria

- [ ] The empty Look inspector has a clear hierarchy: a meaningful title, concise explanation of external Look import/folder setup, and a restrained visual treatment or system icon.
- [ ] The primary import action spans the usable inspector width, has consistent padding, and remains discoverable without competing with the existing folder controls.
- [ ] The action exposes clear hover, pressed, focus, disabled, and import-error states using Lumo's existing SwiftUI/AppKit conventions.
- [ ] The empty state and action remain usable at the supported inspector widths and do not clip or push the tab switcher and recovery messaging off-screen.
- [ ] Existing Looks, missing-file recovery, intensity controls, and application behavior are unchanged when one or more Looks are present.
- [ ] Keyboard navigation, focus visibility, contrast, and VoiceOver/accessibility labels are covered.
- [ ] Add view-level snapshot/manual coverage for empty, scanning/error, missing-reference, and populated states; keep model behavior covered by the existing Look workflow tests.

## Implementation notes

Reuse existing typography, color, spacing, corner-radius, and button primitives in `LumoTheme`, `InspectorDisclosure`, and `LookInspectorView`. Treat “Apple-like” as a quality bar—clarity, restraint, and strong spacing—not as a request to copy proprietary UI.

## Verification

Run the existing Look workflow tests and perform manual visual/accessibility QA at the supported inspector widths for empty, scanning/error, missing-reference, and populated states, including keyboard focus and VoiceOver labels.

## Out of scope

- Bundling new LUT assets; that is LUMO-150.
- Changing LUT parsing, selection, persistence, or render behavior.
