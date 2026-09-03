---
id: LUMO-144
title: Redesign the Looks empty state and add-look action
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ui
  - looks
  - design-system
  - accessibility
created: 2026-09-03T01:12:24.018Z
updated: 2026-09-03T01:12:24.286Z
order: zzy
board: product
---

## Objective

Make the Looks panel feel polished and inviting when empty, with a prominent full-width action for adding the first Look.

## Context

The current Looks empty state feels unfinished and the add action is visually undersized. The redesign should use the app's existing visual language and feel deliberate, calm, and high quality rather than adding decorative complexity.

## Acceptance criteria

- [ ] The empty Looks state has a clear visual hierarchy: meaningful title, concise explanation, and an appropriate visual treatment or illustration/icon.
- [ ] The Add Look action spans the usable sidebar width, has generous and consistent padding, and is easy to discover.
- [ ] The action has clear hover, pressed, focus, disabled, and error states consistent with the design system.
- [ ] The empty state and button remain usable at supported sidebar widths and do not clip or push existing controls off-screen.
- [ ] Existing Looks render correctly when one or more Looks are present; the redesign does not alter Look application behavior.
- [ ] Keyboard navigation, focus visibility, contrast, and VoiceOver/accessibility labels are covered.
- [ ] Add visual/regression coverage for the empty and populated states.

## Implementation notes

Reuse existing typography, color, spacing, corner-radius, and button primitives. Treat “Apple-like” as a quality bar—clarity, restraint, and strong spacing—not as a request to copy proprietary UI.
