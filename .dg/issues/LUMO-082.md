---
id: LUMO-082
title: Copy/Paste Edits shortcuts (⌘C/⌘V) collide with standard text-field copy/paste
type: bug
status: done
priority: medium
labels:
  - verification
  - epic:lut
  - phase:7
created: 2026-09-01T14:08:37.323Z
updated: 2026-09-01T14:44:21.317Z
depends_on:
  - LUMO-043
order: a0
board: product
commits:
  - 41daca6
---

## Objective

Fix a keyboard-shortcut collision introduced by LUMO-043 (commit 282b23b).

## Context

Parent: LUMO-043.

`LumoCommands` (Sources/LumoKit/Views/MenuCommands.swift) adds "Copy All Edits" (⌘C, no modifiers) and "Paste Edits" (⌘V) inside `CommandGroup(replacing: .newItem)` — i.e. the File menu. SwiftUI still supplies the default Edit menu with the system's standard Copy (⌘C) / Paste (⌘V) items (target-action forwarded to the first responder). Two menu items now claim the same key equivalent across different menus.

The app has real text-entry surfaces that need standard clipboard behavior: the "Search looks" field (`LUTSidebar.swift`), and numeric `TextField`s in `EffectsInspectorView.swift` / `ColorInspectorView.swift`. `KeyboardShortcuts.swift`'s `KeyMonitor` already special-cases focused text fields (`NSApp.keyWindow?.firstResponder is NSText`) for its own custom shortcuts, but that guard doesn't apply to SwiftUI `Commands`/`keyboardShortcut`, which dispatch through the AppKit menu key-equivalent system ahead of/independently from that monitor.

Net effect: typing in the search field or a numeric field and pressing ⌘C/⌘V is likely to trigger "Copy All Edits"/"Paste Edits" instead of (or unpredictably alongside) standard text copy/paste, depending on AppKit's menu key-equivalent resolution order.

## Scope

- Give "Copy All Edits" / "Paste Edits" shortcuts that don't collide with system text editing (e.g. ⌘⌥C / ⌘⌥V, matching the pattern already used elsewhere in this menu for Import/Open Source Folder), OR gate the existing shortcuts so they don't fire while a text field has focus.
- Add/extend a test or manual check confirming the Search Looks field and numeric inspector fields retain normal ⌘C/⌘V text editing.

## Acceptance criteria

- [ ] ⌘C/⌘V in the Search Looks field and numeric inspector fields perform standard text copy/paste, not edit-transfer.
- [ ] Copy All Edits / Paste Edits remain reachable via menu and a (non-colliding) shortcut.

## Out of scope

- Any other LUT/persistence behavior from LUMO-043 (already verified).


### Comment — codex @ 2026-09-01T14:44:21.110Z

Implemented in commit 41daca6. Copy All Edits and Paste Edits now use non-colliding ⌘⌥C/⌘⌥V shortcuts, leaving standard ⌘C/⌘V available to the Search Looks and numeric inspector text fields. Updated toolbar help and the README shortcut table. Added MenuCommandTests covering the edit-transfer shortcut contract; this verifies the menu shortcuts include Option and exclude Shift/Control. Verification: swift test — 490 passed, 25 expected skips, 0 failures; swift build -c release — passed; git diff --check — passed; dg validate — OK with the pre-existing runner-model warning.

## Agent log

- 2026-09-01T14:44:21.316Z: Resolved the Copy/Paste Edits shortcut collision by moving edit transfer to ⌘⌥C/⌘⌥V, added regression coverage and documentation, and verified tests/build/validation.
