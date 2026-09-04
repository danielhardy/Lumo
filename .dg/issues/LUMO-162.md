---
id: LUMO-162
title: Remove duplicate no-op Settings menu item
type: bug
status: done
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - settings
  - menu
  - macos
created: 2026-09-03T18:15:23.391Z
updated: 2026-09-03T18:29:33.532Z
order: a0
board: product
commits:
  - af7cdef
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Exactly one Settings command in the app menu
      result: pass
    - criterion: Selecting the command opens/focuses the Settings window
      result: pass
    - criterion: Standard Command-comma shortcut retained and keyboard accessible
      result: pass
    - criterion: No-op top item removed without touching About/Services/Hide/Quit
      result: pass
    - criterion: Menu-command test coverage added
      result: pass
  checks_run:
    - swift build — passed
    - swift test --filter MenuCommandTests — 3 passed
    - swift test (full suite) — passed, 0 failures
    - swift build -c release — passed
    - "dg validate — OK (pre-existing unrelated warning: agents.pickup.runner model)"
  findings: []
  fixes: []
  verification_commits:
    - af7cdef
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-03T18:29:33.526Z
  session: 01MTLUTCT6IYYHHISV
---

## Objective

Remove the duplicate, no-op **Settings…** entry at the top of Lumo’s application menu.

## Context

The application menu currently displays two Settings entries:

1. The top item (shown blue when hovered) uses a distinct gear icon, accepts selection, and does nothing.
2. The standard item below it has the ⌘, shortcut and opens the actual Settings window.

The redundant top item makes the menu look broken and gives users an action that has no result.

## Acceptance criteria

- [ ] The Lumo application menu contains exactly one Settings command.
- [ ] Selecting that command opens or focuses the Settings window.
- [ ] The working command keeps the standard macOS ⌘, shortcut and remains accessible by keyboard.
- [ ] The no-op top Settings item is removed without changing About, Services, Hide, or Quit commands.
- [ ] Add or update menu-command coverage as practical, and verify the menu manually in a built app.

## Likely area

Inspect `Sources/LumoKit/Views/MenuCommands.swift` together with the `Settings` scene in `Sources/Lumo/LumoApp.swift`; the duplicate is likely caused by adding a custom Settings link alongside SwiftUI’s standard Settings command.


### Comment — codex @ 2026-09-03T18:23:54.627Z

Removed the redundant SettingsLink() command group; the native Settings scene now supplies the single Settings… command and standard Command-comma shortcut. Added MenuCommandTests coverage. Verification: swift test (715 passed, 14 expected skips), scripts/build-macos-app.sh, and manual .build/Lumo.app UI check confirmed one Settings item, About/Services/Hide/Quit unchanged, Settings opens, and Command-comma reopens it.

## Agent log

- 2026-09-03T18:29:33.530Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Exactly one Settings command in the app menu (pass)
- [x] Selecting the command opens/focuses the Settings window (pass)
- [x] Standard Command-comma shortcut retained and keyboard accessible (pass)
- [x] No-op top item removed without touching About/Services/Hide/Quit (pass)
- [x] Menu-command test coverage added (pass)
Checks run:
- swift build — passed
- swift test --filter MenuCommandTests — 3 passed
- swift test (full suite) — passed, 0 failures
- swift build -c release — passed
- dg validate — OK (pre-existing unrelated warning: agents.pickup.runner model)
Findings:
- None
Fixes:
- None
Verification commits:
- af7cdef
Actor: claude
Resolved model: sonnet
Pickup session: 01MTLUTCT6IYYHHISV
Summary: Verified: SettingsLink() duplicate removed, native Settings scene supplies the single Settings command. swift test (full suite) and swift build -c release pass; dg validate OK.
