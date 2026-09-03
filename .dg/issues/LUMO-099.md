---
id: LUMO-099
title: Make single-photo editing the default and preserve the last comparison mode
type: task
status: done
priority: high
labels:
  - mvp
  - ux
  - accessibility
  - epic:editor
  - phase:8
created: 2026-09-01T17:47:14.516Z
updated: 2026-09-01T19:15:24.836Z
depends_on:
  - LUMO-047
  - LUMO-049
order: z
board: product
---

## Objective

Make single-photo editing the default, keep side-by-side as an explicit comparison option, and make
the view switch fast and predictable.

## Context

Editing currently opens in a mode that can make the photo feel constrained, while some available
view affordances appear to do nothing. The single-photo canvas should be the primary editing
surface, with a remembered comparison preference and a direct keyboard toggle.

## Acceptance criteria

- [ ] A first-time edit opens in single-photo view; after the user changes modes, the last selected
  mode is reused for subsequent photo opens and relaunches where preferences are supported.
- [ ] Side-by-side remains available as an explicit option and shows original versus adjusted
  content with shared zoom/pan behavior.
- [ ] A documented hotkey (retaining `V` unless a product decision requires otherwise) switches
  immediately between single and side-by-side modes and respects text-field/system-shortcut focus.
- [ ] No visible view-mode control is a no-op: unsupported modes are removed, or their behavior is
  implemented and covered.
- [ ] Add coverage for first-launch default, remembered mode, photo switching, relaunch/persistence,
  and keyboard routing.

## Implementation notes

Relevant code: `AppViewModel` comparison state, `ContentView`, `PreviewView`,
`KeyboardShortcuts`, persistence/preferences, and existing comparison tests. Keep comparison
availability rules from LUMO-047 and accessibility labels synchronized with the actual mode.

### Comment — codex @ 2026-09-01T19:01:28.728Z

Implemented and committed as 775d19b. Made single-photo editing the first-launch default; persisted the last comparison mode in UserDefaults across photo switches and relaunches; preserved the LUMO-047 comparison availability rule; kept side-by-side original/adjusted panels on shared canvas navigation; reset transient Space comparison on photo changes; tightened plain V and Space keyboard routing around text fields, controls, and system modifiers; synchronized toolbar/status accessibility and removed unavailable comparison affordances. Added persistence, relaunch, photo-switch, and keyboard-policy coverage. Verification: swift test (549 passed, 26 expected skips, 0 failures); swift build -c release passed; git diff --check passed; dg validate passed with the pre-existing runner-model warning.

### Comment — claude @ 2026-09-01T19:15:22.221Z

## Counterpoint verification report (independent, post-human-review)

**Scope reviewed:** commit 775d19b (feat(LUMO-099): default to single-photo comparison mode) — AppViewModel.swift, ContentView.swift, KeyboardShortcuts.swift, StatusBar.swift, plus added/extended tests.

**Checks run independently:**
- `swift build` — clean, 0 diagnostics.
- `swift test --filter ComparisonModeTests|KeyMonitorTests` — all pass (4+4 = 8 tests).
- `swift test` (full suite) — 557 executed, 26 skipped, 0 failures. (Count differs from the implementer's reported 549 because LUMO-101 landed additional tests since; no LUMO-099-related failures.)
- `swift build -c release` — clean, 0 diagnostics.
- `git diff --check` on the commit — clean.
- `dg validate` — OK, only the pre-existing `agents.pickup.runner` model warning (unrelated to this issue).

**Correctness against acceptance criteria:**
- First-time default: `isSideBySide` now defaults to `false` and is only overridden from `UserDefaults` (`Lumo.editor.comparisonMode.sideBySide`) when a stored value exists — confirmed by `testFirstLaunchDefaultsToSinglePhoto`.
- Persistence across photo switches and relaunch: `didSet` writes through to `preferences` only on actual change; a fresh `AppViewModel` reads it back in `init`. Confirmed by `testSelectedModeIsRememberedAcrossRelaunch`, `testReturningToSinglePhotoModeIsAlsoRemembered`, and `testSelectedModeSurvivesPhotoSwitch`. Transient Space/`isShowingOriginal` state is correctly reset on photo change (`loadImage` reset) and does not leak into the persisted preference.
- Side-by-side availability gate (`isComparisonAvailable`) from LUMO-047 is preserved and reused consistently for the toolbar control, status bar hint, and Space handling.
- Keyboard routing: existing text-input/system-modifier gating (`globalShortcutsOwnKeyboard`, `hasSystemModifier`) already covers focus/system-shortcut deference ahead of the `v`/Space cases; the new `isPlainCharacterShortcut` check additionally filters Shift-V, which the prior gates didn't catch on their own (Shift isn't one of `hasSystemModifier`'s tracked modifiers). Verified via `testGlobalShortcutsDeferToTextInputAndSystemModifiers` and the new `isPlainCharacterShortcut` unit assertions.
- No-op affordance removal: the side-by-side toolbar button and its status-bar hint are now conditionally rendered only when `isComparisonAvailable`, instead of a permanently-visible-but-disabled control — matches "no visible view-mode control is a no-op."
- Shared zoom/pan behavior in side-by-side (`PreviewView`) was untouched by this diff and remains intact.

**No blockers found.** No localized fixes were needed. No new child tickets required — this closes cleanly.

Verdict: **PASS**. Moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T19:15:24.834Z: Independent verification passed: build/test/release/dg-validate all green; default, persistence, availability gate, and keyboard routing all confirmed correct against acceptance criteria. No blockers.
