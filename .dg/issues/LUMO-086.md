---
id: LUMO-086
title: Replace wide inspector tab labels with a compact icon-based switcher
type: task
status: done
priority: medium
labels:
  - mvp
  - ux
  - accessibility
created: 2026-09-01T14:35:33.953Z
updated: 2026-09-01T15:47:27.908Z
order: zzzzx
board: product
---

## Objective

Reduce the inspector view switcher's visual footprint by using recognizable icons with hover help
instead of full-width text labels.

## Context

`InfoInspectorView.tabSwitcher` currently renders every inspector tab as a text segmented picker.
With several tabs this consumes valuable sidebar width and competes with the editing controls.
The compact form must remain discoverable and usable with keyboard navigation, VoiceOver, and a
pointer; icons should communicate Info, Light, Develop, Color, Effects, and Look unambiguously.

## Acceptance criteria

- [ ] The switcher uses compact icons for each available inspector tab and no longer requires the
  full tab titles to fit side by side.
- [ ] Hovering/focusing an icon exposes its full tab name and purpose through a tooltip/help label.
- [ ] Selected, pressed, disabled, and keyboard-focus states are visually clear in both appearances.
- [ ] Keyboard navigation and VoiceOver announce each tab's full name; the compact treatment does
  not reduce the hit target below a usable size.
- [ ] The switcher adapts correctly when Develop is conditionally hidden by LUMO-092.

## Implementation notes

Relevant code: `Sources/LumoKit/Views/InfoInspectorView.swift` and
`AppViewModel.InspectorTab`. Keep tab selection state and existing histogram behavior unchanged.

### Comment — codex @ 2026-09-01T15:45:14.325Z

Implemented compact icon-based inspector tabs in commit a2f76f8. InspectorTab now provides SF Symbol names and panel-purpose copy; the segmented switcher renders icon-only labels with hover help, VoiceOver labels/hints/selection values, large hit targets, and existing native keyboard/selection states. Conditional Develop availability remains driven by availableInspectorTabs. Verification: swift test (506 passed, 26 expected skips), swift test --filter AdjustInspectorTests (17 passed), swift build -c release, git diff --check, and dg validate passed; validate reports only the pre-existing pickup-runner model warning.

### Comment — claude @ 2026-09-01T15:47:25.706Z

## Counterpoint verification — PASS

Independent review of commit a2f76f8 (compact icon-based inspector tab switcher) after human review.

**Correctness**
- `InspectorTab.iconName` gives each of the 6 tabs a distinct, semantically fitting SF Symbol (info.circle, sun.max, camera.aperture, paintpalette, sparkles, wand.and.stars) — no collisions.
- Switcher iterates `viewModel.availableInspectorTabs`, which already filters Develop via `developPanelState.offersDevelopTab` (LUMO-092's gating). No new logic needed here — the compact switcher inherits that behavior for free. Confirmed by reading `AppViewModel.InspectorTab.availableTabs` and `applyTabFallbackIfNeeded`.
- `.tag(tab)` + `Picker(selection:)` preserves existing selection-state plumbing; no new state introduced.

**Accessibility**
- Each segment carries `accessibilityLabel` (full title), `accessibilityHint` (purpose), and `accessibilityValue` (selection state) independent of the icon-only `.labelStyle`, satisfying the VoiceOver acceptance criterion at the code level.
- `.help(tab.helpText)` supplies the hover tooltip text combining title + purpose.
- Note (non-blocking): SwiftUI's propagation of `.help()`/accessibility modifiers from a segmented `Picker`'s per-item label content to the underlying `NSSegmentedControl` is a known platform-version-sensitive area. This wasn't independently verified via manual hover in a running app window (no interactive UI-automation tooling available in this environment). Recommend a quick manual hover/VoiceOver pass in Xcode as a follow-up, but not blocking given the code-level implementation is correct and consistent with SwiftUI's documented `.help` behavior.
- "Disabled" state from the acceptance criteria doesn't apply in practice — tabs are filtered out of `availableInspectorTabs` rather than shown disabled, consistent with the existing LUMO-092 pattern (hide, don't disable).

**Checks run**
- `swift build` — clean.
- `swift test` — 506 passed, 26 expected skips, 0 failures.
- `swift build -c release` — succeeds (only pre-existing, unrelated Core Image kernel deprecation warnings).
- `git diff --check` — clean.
- `dg validate` — OK (only the pre-existing pickup-runner model warning).

No blockers found. No localized fixes needed — nothing to change.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
