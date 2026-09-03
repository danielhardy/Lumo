---
id: LUMO-141
title: Open the Info inspector after the first successful Photos import
type: feature
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - import
  - ux
  - navigation
created: 2026-09-03T01:12:22.295Z
updated: 2026-09-03T01:12:22.591Z
depends_on:
  - LUMO-129
estimate: 2
order: zzy
board: product
---

## Objective

After the first successful item in a Photos import, open Lumo's existing right-side Info inspector so the imported photo is immediately ready for inspection and editing.

## Context

The current Photos import path streams items through `ImageCollection`, opens the first successful item through `AppViewModel`, and leaves inspector presentation unchanged. The product surface is the SwiftUI `.inspector` containing `InfoInspectorView`; this ticket is about that presentation state, not adding another sidebar or redesigning inspector tabs. The first successful item is the import's active edit photo even when later items are still transferring.

## Acceptance criteria

- [ ] The first successful Photos import item opens the existing Info inspector and the inspector is presented for that active item.
- [ ] A multi-item import opens the inspector once for the first successful item, even if later transfers are still in progress; later items must not retarget it unexpectedly.
- [ ] The presented inspector shows the selected photo's current metadata/histogram state and does not retain stale content from the previously active photo.
- [ ] Cancellation before any accepted item, an empty selection, and an import in which every item fails leave the inspector presentation unchanged.
- [ ] Repeated imports are idempotent: they do not create duplicate panels, change the selected inspector tab, or reset unrelated inspector preferences.
- [ ] Automated view-model/state coverage exercises first-success, partial-success, all-failure, cancellation, and repeated-import paths; the existing mouse/keyboard import entry points remain covered by the same state transition.

## Implementation notes

Trace the import-completion event through `AppViewModel` selection and `InspectorState.isPresented` rather than coupling the behavior to `PhotosPicker` implementation details. Preserve the existing selected tab and Info-inspector state model where possible.

## Out of scope

- Changing the Library/Edit navigation mode, source-folder browser, or Open Image behavior.
- Adding new inspector tabs or changing when histogram work is scheduled.
