---
id: LUMO-160
title: "Fix(LUMO-155): commit missing Settings entry point so Always-dark-mode toggle is reachable"
type: bug
status: done
priority: urgent
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - appearance
  - settings
  - macos
created: 2026-09-03T15:08:14.723Z
updated: 2026-09-03T15:31:04.280Z
parent: LUMO-155
order: zzzzzzy
board: product
---

## Objective

Commit the Settings scene, `SettingsLink()` menu item, and `LumoSettingsView` that
let a user actually open Settings and toggle **Always dark mode**, so LUMO-155's
fix (`LumoWindowAppearanceController`) is reachable in the shipped app.

## Context

Counterpoint verification of LUMO-155 (commit `d67e322`) found that the committed
diff only adds the window-level appearance propagation machinery
(`LumoWindowAppearanceController`), but never commits the UI needed to reach the
"Always dark mode" toggle:

- `Sources/Lumo/LumoApp.swift` has no `Settings { }` scene at `d67e322` (HEAD).
- `Sources/LumoKit/Views/MenuCommands.swift` has no `SettingsLink()` menu item.
- `Sources/LumoKit/Views/LumoSettingsView.swift` was never committed at all
  (confirmed with `git cat-file -e HEAD:...` → missing).

A clean checkout of `d67e322` (verified via `scripts/agent-worktree.sh create HEAD`)
therefore has **no way to open Settings** — the app has zero menu item or keyboard
shortcut for it, because SwiftUI only adds the Settings… command when the `App`
declares a `Settings` scene. The reported bug ("open Lumo's Settings and enable
Always dark mode") cannot be reproduced or exercised against the actual git
history; it only "worked" against the implementer's local uncommitted working
tree (which does have `Settings { LumoSettingsView(...) }`, `SettingsLink()`, and
`LumoSettingsView.swift` on disk, untracked). The completion comment's claim of
"swift test — 700 passed... swift build -c release passed" was evaluated against
that uncommitted tree, not against the committed commit.

Separately, a clean checkout of HEAD does not even compile — see [[LUMO-161]] for
that pre-existing, unrelated build break.

## Acceptance criteria

- [ ] `Sources/Lumo/LumoApp.swift` declares a `Settings { }` scene presenting the
      Settings UI (the currently-untracked `LumoSettingsView.swift` or equivalent),
      committed to the branch.
- [ ] A menu item (e.g. `SettingsLink()` under `CommandGroup(after: .appInfo)`) or
      the platform-standard ⌘, shortcut opens it, committed to the branch.
- [ ] From a clean checkout, a user can open Settings, toggle "Always dark mode",
      and see the main window/app shell update live per LUMO-155's acceptance
      criteria — verified against `git` HEAD, not a working tree with uncommitted
      files.
- [ ] `swift build` and `swift test` pass from a fresh `git worktree` checkout of
      the branch (no reliance on untracked files).

## Implementation notes

Coordinate with whichever ticket owns the Look/LUT "Save as Look/LUT…" work
(LUMO-152/153/154 family) since the untracked `LumoSettingsView.swift`,
`LookSaveSheet.swift`, `CubeLUT.swift`/`LUTLibrary.swift` API changes, and
`MenuCommands.swift` menu additions currently sitting uncommitted in the working
tree appear to be one in-flight, interdependent feature. Committing the Settings
scene in isolation may require pulling in only the settings-relevant subset
rather than the whole uncommitted diff.
