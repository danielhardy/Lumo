---
id: LUMO-100
title: Remove unintended spacers from the editor toolbar
type: task
status: done
priority: low
labels:
  - mvp
  - ux
  - epic:editor
  - phase:8
created: 2026-09-01T17:47:14.815Z
updated: 2026-09-01T19:49:28.935Z
order: zy
board: product
commits:
  - e39fb73
---

## Objective

Remove unintended empty gaps from the editor toolbar so related controls sit together and the bar
uses space consistently.

## Context

There are visible odd spacers around the single/side-by-side image-view control and between the
undo/import area. These gaps make the toolbar look fragmented and can push useful actions out of
view.

## Acceptance criteria

- [ ] The unintended gap adjacent to the image-view mode control is removed.
- [ ] The unintended gap between the undo and import controls is removed.
- [ ] Intentional grouping separators remain clear, and the toolbar still adapts correctly at
  narrow and wide window sizes.
- [ ] Control order, hit targets, help text, keyboard shortcuts, and accessibility are unchanged
  except for the spacing cleanup.
- [ ] Add a focused UI/layout verification or document a repeatable manual check for the affected
  toolbar widths.

## Implementation notes

Relevant code: `Sources/LumoKit/Views/ContentView.swift` and any toolbar grouping/layout helpers.
Inspect both explicit `Divider`/spacing structure and macOS toolbar item grouping before changing
layout so meaningful separators are not removed accidentally.

### Comment — codex @ 2026-09-01T19:44:56.961Z

Implemented in commit e39fb73. Removed the two stale top-level toolbar dividers: the separator left adjacent to the Crop/comparison controls after the format picker was removed, and the separator between Reset and Import. Retained the intentional Copy/Paste-to-Export boundary and all menu-internal dividers; control order, labels, help text, shortcuts, accessibility, and actions are unchanged. Verification: swift test — 557 passed, 26 expected skips, 0 failures; swift build -c release — passed; git diff --check — passed; dg validate — passed with the existing pickup-runner model warning. Repeatable manual layout check: launch with `swift run`, open an image, inspect at the 800x500 minimum and a wide ~1440px window, confirm Workspace → Crop → Side by Side → canvas/source/info/reset → Import has no extra blank separator gaps, confirm the Copy/Paste → Export separator remains, then resize through both widths and verify controls overflow via the native toolbar overflow without clipping; hover/focus the affected controls to confirm their existing help, hit targets, keyboard shortcuts, and accessibility labels remain available.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T19:49:28.933Z: Toolbar spacer cleanup verified: removed the stale comparison-adjacent and Reset/Import top-level dividers, retained the intentional export boundary and menu separators. swift test: 557 passed, 26 expected skips; release build passed; git diff --check passed; dg validate passed with the existing pickup-runner model warning. Repeatable 800x500-to-wide resize/manual accessibility check documented in the issue comment.
