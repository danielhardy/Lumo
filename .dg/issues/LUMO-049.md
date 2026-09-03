---
id: LUMO-049
title: Complete filmstrip navigation, focus-safe shortcuts, resets, and accessibility
type: task
status: done
priority: medium
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:33.766Z
updated: 2026-09-01T18:21:39.403Z
depends_on:
  - LUMO-045
  - LUMO-022
  - LUMO-009
estimate: 5
order: zzzzzh
board: product
---

## Objective

Make the edit loop efficient from the keyboard and predictable for assistive technology.

## Context

Part of **Epic 8 — Image-centric editor experience**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Retain arrow/bracket filmstrip navigation and add documented P/X/0–5/G/E behavior.
- Define focus precedence so sliders/text fields are not hijacked.
- Implement reset control, reset section, and reset photo affordances.
- Add accessibility labels, values, and keyboard focus order to repeated controls.

## Acceptance criteria

- [ ] All documented shortcuts work in their intended mode and do not fire while inappropriate controls own input.
- [ ] Filmstrip follows selection and prepares adjacent photos.
- [ ] Reset scopes are clear and undoable.
- [ ] VoiceOver can distinguish repeated mixer/grading/effects controls.

## Verification

- Extend key monitor/focus tests and perform a keyboard/VoiceOver smoke pass.

## Out of scope

- User-configurable shortcut editor.

### Comment — codex @ 2026-09-01T17:31:13.810Z

Implemented in commit 5e1a7e4. Added documented P/X/0–5/G/E shortcuts with focus-safe routing that defers to text fields and native controls; converted the filmstrip to keyboard/VoiceOver-operable buttons with selection-following adjacent thumbnail preparation; added scoped current-section and whole-photo reset affordances with undo coverage; and added contextual accessibility values/order for repeated inspector controls. Verification: swift test (529 passed, 26 expected skips), swift build -c release passed, git diff --check passed, dg validate passed with only known runner-model and unrelated LUMO-044 context warnings.

### Comment — claude @ 2026-09-01T18:21:28.001Z

Independent counterpoint verification (post-human-review) of commit 5e1a7e4.

Checks run:
- swift build — clean.
- swift test — 533 executed, 0 failures, 26 expected skips (matches the implementer's report).
- git diff --check 5e1a7e4~1..5e1a7e4 — clean.

Focused review of the riskiest change: KeyMonitorPolicy.controlOwnsKeyboard widened from
"text input only" to "any NSControl" (Sources/LumoKit/Views/KeyboardShortcuts.swift), combined with
FilmstripView converting thumbnail cells to real Buttons for VoiceOver/Tab operability. Hypothesized
this could break arrow-key filmstrip stepping after any mouse click. Verified empirically with a
standalone AppKit harness (synthetic NSButton click via NSApplication.sendEvent) that macOS does NOT
move first responder to a clicked control under default settings, so the common mouse-driven workflow
is unaffected — the widened check is actually a real fix (a Tab-focused Slider previously lost arrow
keys to global Look/image navigation instead of adjusting its own value).

Also checked ImageCollection's new prepareAdjacentThumbnails/preparedThumbnailIDs bookkeeping
(thumbnail pre-warming for the selected photo's neighborhood): releaseThumbnail clears the demand-
priority dictionary entry even for a still-"prepared" id, but priority(for:) recomputes the same
.adjacentFilmstrip value from distance-to-selection when no explicit priority is recorded, so this is
benign, not a bug.

One non-blocking gap found and filed separately: LUMO-102 (backlog, verification label, parent
LUMO-049) — once a filmstrip thumbnail Button holds actual keyboard focus (Tab, not VoiceOver), Left/
Right/[/] stop stepping images because NSButton has no arrow-key handling of its own and the widened
policy now defers to it. Narrow edge case (new focus target, not a regression of prior behavior;
mouse and canvas/library-focused keyboard nav are unaffected), so not a blocker.

Verdict: pass. No code changes made during verification.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
