---
id: LUMO-147
title: Save a set of compatible edits as a LUT
type: feature
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - lut
  - edits
  - export
  - color
created: 2026-09-03T01:12:25.648Z
updated: 2026-09-03T01:12:25.932Z
order: zzy
board: product
---

## Objective

Let users save the color edits applied to a photo as a reusable LUT.

## Context

Users can create a look through the editor but cannot currently preserve it as a LUT. The feature must distinguish color-transform edits that can be represented in a LUT from edits such as crop or geometry that cannot.

## Acceptance criteria

- [ ] A Save as LUT action is available from the editing workflow when a photo is loaded.
- [ ] The action opens a save flow that collects a name, validates it, and saves a standard LUT file; the supported format, color space, range, and resolution are documented.
- [ ] Supported color edits are baked into the LUT; non-LUT-editable edits are not silently encoded.
- [ ] If the current edit set contains unsupported operations, the UI clearly explains what will be omitted and lets the user cancel before saving.
- [ ] A saved LUT appears in the Looks/LUT browser with its name and preview, and can be applied to another photo.
- [ ] Applying the saved LUT to a representative photo produces a result consistent with the source color edits within the documented conversion limits.
- [ ] Name collisions, invalid destinations, cancellation, and write failures are recoverable and do not mutate the current photo's edits.
- [ ] Automated coverage verifies conversion, unsupported-edit messaging, persistence, browser visibility, and round-trip application.

## Implementation notes

Define the edit-to-LUT support matrix before implementation. Keep crop, rotation, masking, local adjustments, and other spatial operations out of the LUT unless the renderer explicitly supports an equivalent global color transform. Coordinate the canonical storage location with the Settings ticket.
