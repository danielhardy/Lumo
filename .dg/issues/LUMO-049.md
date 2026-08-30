---
id: LUMO-049
title: Complete filmstrip navigation, focus-safe shortcuts, resets, and accessibility
type: task
status: backlog
priority: medium
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:33.766Z
updated: 2026-08-30T18:30:51.372Z
depends_on:
  - LUMO-045
  - LUMO-022
  - LUMO-009
estimate: 5
order: za2voh9x
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
