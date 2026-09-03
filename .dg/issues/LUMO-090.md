---
id: LUMO-090
title: Make accordion titles fully clickable with animated open and close
type: task
status: done
priority: medium
labels:
  - mvp
  - ux
  - accessibility
created: 2026-09-01T14:35:35.133Z
updated: 2026-09-01T16:18:17.824Z
order: a0
board: product
---

## Objective

Make every accordion/disclosure title clickable across its full row, with a clear animated open and
close transition.

## Context

The inspector uses multiple nested disclosure groups for Tone, Tone Curve, Color, Mixer channels,
grading zones, and Effects. The current native affordance can leave only the small chevron as the
obvious target, which makes repeated panel navigation unnecessarily precise.

## Acceptance criteria

- [ ] Clicking anywhere on a section's title row, including its text and trailing empty space,
  toggles that section; the chevron remains usable.
- [ ] Expansion and collapse animate consistently without clipping, jumping scroll position, or
  losing the section's controls/state.
- [ ] Nested mixer and grading accordions behave independently and do not toggle their parent.
- [ ] The full title row exposes the correct toggle role/value to VoiceOver and remains keyboard
  operable.
- [ ] Add focused interaction/state coverage or a documented manual smoke test for every inspector
  that uses an accordion.

## Implementation notes

Audit `DisclosureGroup` usage in `LightInspectorView.swift`, `ColorInspectorView.swift`, and
`EffectsInspectorView.swift`. Prefer a shared title-row primitive or a carefully styled native
disclosure so accessibility and animation semantics remain intact.

### Comment — codex @ 2026-09-01T16:16:12.920Z

Implemented in commit d79c0a3. Replaced all Light, Color, and Effects DisclosureGroup usages with the shared full-width InspectorDisclosure row, including nested mixer channels and grading zones. The row is keyboard-operable, exposes explicit toggle state to VoiceOver, animates open/close without clipping, and keeps nested bindings independent. Added docs/INSPECTOR_DISCLOSURES.md with the focused mouse, state, keyboard, and VoiceOver smoke-test matrix. Verification: swift test — 510 passed, 26 expected skips, 0 failures; swift build -c release passed; git diff --check passed; dg validate passed with only the known pickup-runner model warning.

### Comment — claude @ 2026-09-01T16:18:15.360Z

## Independent verification — counterpoint agent

**Scope reviewed:** commit d79c0a3 (InspectorDisclosure.swift + Light/Color/Effects inspector call sites + docs/INSPECTOR_DISCLOSURES.md).

**Acceptance criteria**
- Full-row click target: PASS. `InspectorDisclosure` wraps title+chevron+trailing space in one `Button` with `.contentShape(Rectangle())` and `.frame(maxWidth: .infinity, alignment: .leading)`; chevron sits inside the same button.
- Animated open/close, no clipping/scroll jump: PASS by inspection. Content is conditionally inserted with `.transition(.opacity)` under `.animation(.easeInOut(duration: 0.2), value: isExpanded)`; no `.clipped()`/height tricks that would truncate content, and section state is plain `@State`/`Binding` so it isn't reset on toggle.
- Nested mixer/grading rows independent of parent: PASS. Verified `mixerExpansion(for:)` / `gradingExpansion(for:)` (ColorInspectorView.swift:262-278) key off a `Set<Channel/Zone>`, giving each nested row its own binding; SwiftUI `Button`s don't bubble, so a child toggle can't fire the parent's action.
- VoiceOver role/value + keyboard operability: PASS. Row exposes `.accessibilityLabel`, `.accessibilityValue("Expanded"/"Collapsed")`, `.accessibilityAddTraits(.isToggle)` with `.isButton` removed, and hint text. It's a real `Button`, so Space/Return activation and Tab focus work the same as any other control in the inspector — no custom gesture recognizer to fight the system.
- Interaction/state coverage or documented manual smoke test: PASS (via the "or"). No automated tests target `InspectorDisclosure` directly (SwiftUI view state isn't unit-testable here), but `docs/INSPECTOR_DISCLOSURES.md` documents a concrete mouse/state/keyboard/VoiceOver matrix covering every inspector and nested section listed in the issue.

**Checks run**
- `swift build` — clean.
- `swift test` — 510 passed, 26 expected skips, 0 failures (matches the implementer's self-report).

**Non-blocking observation (not filed as a ticket):** the working tree currently also carries unrelated, unstaged WIP (a color-grading wheel control and several new `.dg/issues/LUMO-08x`/`09x` files) that predates this verification pass and is untouched by d79c0a3. Flagging for visibility only — it's out of scope for LUMO-090 and was left as-is.

**Verdict: PASS.** No blocking issues found; no localized fixes needed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T16:18:17.823Z: Independent verification passed: full-row click target, animated open/close, independent nested toggles, VoiceOver/keyboard support, and documented smoke-test coverage all confirmed against commit d79c0a3. swift build/test clean (510 passed, 0 failures).
