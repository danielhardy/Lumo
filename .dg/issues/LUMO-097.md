---
id: LUMO-097
title: Remove the Look button from the top toolbar
type: task
status: done
priority: medium
labels:
  - mvp
  - ux
  - epic:editor
  - phase:8
created: 2026-09-01T17:47:13.799Z
updated: 2026-09-01T19:46:29.025Z
depends_on:
  - LUMO-085
order: zzzzzx
board: product
---

## Objective

Remove the dedicated `Look` button from the top toolbar to reduce duplicated navigation chrome.

## Context

The Look stage already has a canonical inspector surface and tab. The toolbar button duplicates
that entry point and competes with the image/editor controls.

## Acceptance criteria

- [ ] The top toolbar no longer renders a button labeled or identified as `Look`.
- [ ] The Look inspector remains reachable through the canonical inspector tab and existing
  supported navigation paths.
- [ ] Removing the button does not remove Look selection, intensity, auditioning, derive, reset,
  persistence, or keyboard behavior.
- [ ] Update navigation/accessibility coverage to prove there is still one discoverable Look entry
  point.

## Implementation notes

Relevant code: `Sources/LumoKit/Views/ContentView.swift`, `InfoInspectorView`,
`LookInspectorView`, and navigation tests. Keep the user-facing Look stage and persisted LUT state
unchanged; this ticket is toolbar cleanup only.

### Comment — codex @ 2026-09-01T19:38:43.148Z

Implemented in 851f17c. Removed the dedicated Look button from ContentView and its toolbar-only showLookInspector action; the existing Info inspector tab remains the sole Look entry point with its icon, title, purpose, help, and VoiceOver metadata. Updated LUT workflow coverage to assert one accessible Look inspector tab without changing Look selection, intensity, auditioning, derive, reset, persistence, or keyboard behavior. Verification: swift test — 557 passed, 26 expected skips; swift build -c release passed; git diff --check passed; dg validate passed with the pre-existing unknown pickup-runner model warning.

### Comment — claude @ 2026-09-01T19:46:26.442Z

## Counterpoint verification report

Independent re-verification of commit 851f17c (toolbar Look button removal).

**Checks run:**
- `swift test`: 557 passed, 26 expected skips, 0 failures.
- `swift build -c release`: succeeded.
- `git diff --check`: clean.
- `git status --porcelain`: clean tree, no side-effect edits from this review.

**Code review findings:**
- `ContentView.swift` no longer renders a toolbar button labeled/identified `Look`; `AppViewModel.showLookInspector()` was removed along with it — no dangling references anywhere in `Sources/` or `Tests/`.
- `InfoInspectorView`'s segmented tab picker iterates `viewModel.availableInspectorTabs`, which always includes `.look` whenever an image is loaded (`InspectorTab.availableTabs` only conditionally excludes `.develop`) — Look remains reachable via exactly one inspector tab, with full accessibility metadata (`accessibilityLabel`, `accessibilityHint`, `accessibilityValue`, `.help`).
- `LookInspectorView` (selection, intensity slider, audition, derive, reset, persistence) is untouched by the diff — only the toolbar entry point and its dedicated view-model action were removed.
- Menu commands (`Choose Look Folder...`, `Import Look...`, `Derive Look from JPG…` in `MenuCommands.swift`) are unrelated pre-existing navigation paths, not remnants of the removed button.
- Updated test `testLookIsDiscoverableThroughOneAccessibleInspectorTab` correctly asserts a single `.look` entry in `availableTabs` plus its title/icon/purpose metadata, replacing the toolbar-action test that no longer applies.

**Verdict:** All acceptance criteria satisfied. No blockers, no follow-up tickets needed — this was a clean, localized removal with no residual coupling.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
