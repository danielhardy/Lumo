---
id: LUMO-102
title: "LUMO-049 follow-up: filmstrip loses arrow-key stepping while a thumbnail button holds keyboard focus"
type: task
status: done
priority: low
labels:
  - verification
created: 2026-09-01T18:20:58.370Z
updated: 2026-09-01T21:07:53.861Z
depends_on:
  - LUMO-049
order: a0
board: product
commits:
  - c5ef031
---

## Objective

LUMO-049 follow-up: filmstrip loses arrow-key stepping while a thumbnail button holds keyboard focus

## Context

LUMO-049 (commit 5e1a7e4) widened `KeyMonitorPolicy.controlOwnsKeyboard` from "text input only" to
"any `NSControl`", and converted filmstrip cells from a bare `onTapGesture` view to a real `Button`
(`Sources/LumoKit/Views/FilmstripView.swift`) so VoiceOver/Tab can reach them individually. Both
changes are correct in isolation — the widened check is what makes a Tab-focused slider keep arrow
keys for its own value (previously a real bug), and the filmstrip needed to become focusable at all
to satisfy the VoiceOver acceptance criterion.

The combination leaves a gap: `NSButton` has no built-in arrow-key handling, so once a keyboard-only
(non-VoiceOver) user Tabs onto a filmstrip thumbnail, `KeyMonitor.handle(_:)`
(`Sources/LumoKit/Views/KeyboardShortcuts.swift:112`) now defers to that button and Left/Right/`[`/`]`
stop stepping through images — there's no replacement key handling on the button itself, so keyboard
navigation of the filmstrip dead-ends until focus moves elsewhere (e.g. Tab again, or a click, which
empirically does *not* transfer first responder under default AppKit settings).

Confirmed empirically (not just read from the diff): a synthetic `NSButton` click via
`NSApplication.sendEvent` does not change `window.firstResponder` under default settings, so the
common mouse-driven workflow is unaffected. The gap is specifically for keyboard-only Full-Keyboard-
Access users who Tab into the filmstrip; VoiceOver users are likely unaffected since VO intercepts
arrow keys before the app sees them.

Not a blocker: it only affects a Tab-focused filmstrip button (a newly-added focus target, not a
regression of prior behavior), and the primary interactions (mouse selection, and arrow-key stepping
whenever focus is on canvas/library) are unaffected per the passing test suite and empirical check.

## Acceptance criteria

- [ ] While a filmstrip thumbnail button holds keyboard focus, Left/Right (or `[`/`]`) still steps
      the selection to the adjacent photo — either by having the button itself handle those keys, or
      by scoping `controlOwnsKeyboard` more narrowly than "any `NSControl`" for plain activation
      buttons that aren't editable (sliders/pickers should keep the current deferral).

## Implementation notes

Likely smallest fix: give `FilmstripThumbnail`'s `Button` (or the monitor) explicit Left/Right
handling that calls the same `selectPrevious`/`selectNext` path already used by the global shortcut,
scoped to when a filmstrip button is first responder.

### Comment — codex @ 2026-09-01T21:05:22.615Z

Implemented in commit c5ef031. Focused filmstrip thumbnail buttons now handle Left/Right through SwiftUI key-press handling while preserving global deferral for native controls. Navigation follows filtered display order, routes through the existing onSelect path for edit-mode loading, and stops cleanly at either end. Added FilmstripNavigation coverage for filtered adjacency and boundaries. Verification: swift test — 559 passed, 26 skipped, 0 failures; swift build -c release — passed; git diff --check — passed; dg validate — passed with existing pickup-model and unrelated LUMO-104 context warnings.

### Comment — claude @ 2026-09-01T21:07:50.019Z

Counterpoint verification: PASS.

Reviewed commit c5ef031 independently (correctness, maintainability, security, performance).

- FilmstripNavigation.adjacentIndex (FilmstripView.swift) is an exact restatement of the filteredIndices.last{<}/first{>} logic already used by ImageCollection.selectNext()/selectPrevious(), so filmstrip stepping and the global shortcut path stay in sync; onSelect(adjacentIndex, false) routes through the same selectCollectionImage(at:additive:) used by mouse selection, so edit-mode loading and thumbnail priority behave identically to existing navigation.
- Confirmed KeyMonitorPolicy.controlOwnsKeyboard is unchanged (still "any NSControl") — the fix restores Left/Right locally via .onKeyPress on the focused button rather than narrowing the global policy, so the slider/picker deferral this widened check was added for in LUMO-049 is untouched. `[`/`]` remain deferred to the control while a thumbnail has focus; AC only requires one of the two key sets to work, satisfied by Left/Right.
- No security or performance concerns: pure array scan over filteredIndices (already O(n) at call sites), no new state, no public API/schema change.
- Re-ran independently: swift build (debug) clean; swift test — 559 passed, 26 skipped, 0 failures, matching the implementer's report; git status/diff --check clean, no stray tracked-file edits.

No blockers found. No child tickets needed — this is a self-contained, adequately-tested fix with no broader follow-up warranted.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T21:07:53.858Z: Independent verification passed: restored Left/Right filmstrip stepping via onKeyPress reuses existing FilmstripNavigation/selectNext/selectPrevious logic; no policy widening; full suite green (559/0); no blockers or follow-ups needed.
