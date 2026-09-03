---
id: LUMO-047
title: Unify before/after comparison for every edit stage
type: task
status: done
priority: high
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:32.976Z
updated: 2026-09-01T17:07:56.443Z
depends_on:
  - LUMO-045
  - LUMO-014
estimate: 3
order: a0
board: product
commits:
  - d85409a
---

## Objective

Make Space-hold and side-by-side comparison work for Light, Color, Effects, LUT, and crop policy with an explicit baseline.

## Context

Part of **Epic 8 — Image-centric editor experience**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define before as developed source with the documented RAW baseline.
- Use shared cached intermediates so comparison is cheap.
- Prevent stale original renders during photo/develop changes.
- Support temporary Space behavior without stealing text-field input.

## Acceptance criteria

- [ ] Comparison is available exactly when a visible look-stage edit exists.
- [ ] Both views share orientation, crop policy, zoom, and color handling.
- [ ] Holding/releasing Space is immediate from cache where possible.
- [ ] Keyboard handling respects focused text controls and system shortcuts.

## Verification

- Add comparison-availability, baseline, stale-render, and shortcut-focus tests.

## Out of scope

- Reference-photo comparison.

### Comment — codex @ 2026-09-01T17:05:24.095Z

Implemented in d85409a. Centralized visible look-stage comparison availability and added an explicit developed-source comparison baseline covering Light, Color, Effects, adjustment nodes, and LUTs. Shared baseline work now survives look edits, invalidates on source/RAW-develop/history changes, and rejects stale publications. Side-by-side visibility and toolbar/status affordances follow availability; Space/V routing defers to text fields and system modifiers. Added baseline, availability, stale-render lifecycle, and shortcut-focus policy coverage. Verification: swift test — 524 passed, 26 expected skips; swift build -c release — passed; git diff --check — passed; dg validate — passed with pre-existing runner-model and LUMO-044 context warnings.

### Comment — claude @ 2026-09-01T17:07:52.754Z

Independent counterpoint verification (post-human-review), covering d85409a.

Scope reviewed: AppViewModel.swift (comparisonRevision/documentRevision split, isComparisonAvailable, isSideBySideVisible, showOriginal/toggleSideBySide guards), EditDocument.swift (hasVisibleLookEdits, comparisonBaseline), KeyboardShortcuts.swift (KeyMonitorPolicy, Space/system-modifier gating), and the ContentView/PreviewView/StatusBar consumers.

Findings:
- Baseline invalidation is correctly split: comparisonRevision only advances on RAW-develop/source changes, not look-stage edits (setLookIntensity, updateDocument for Light/Color/Effects/adjustments/LUT) — matches the "cheap from cache" requirement.
- isComparisonAvailable now single-sourced from EditDocument.hasVisibleLookEdits; all UI call sites (toolbar button, PreviewView split, StatusBar hint, InfoInspectorView label) consume the same derived isSideBySideVisible/isComparisonAvailable, so no drift between affordances.
- updateDocument clears isShowingOriginal when a document no longer has visible look edits (e.g. undo/reset), preventing a stuck original-only view.
- showOriginal(true) and toggleSideBySide() both no-op without a visible look edit; showOriginal cleanly exits an active original view if the underlying edit is removed while held.
- KeyMonitorPolicy centralizes text-field deference and Option/Control system-modifier deference before the Space/arrow switch; Space additionally checks isPlainSpace. Verified this doesn't regress the existing Command-A/Command-Z branch (returns early before the new checks).
- comparisonBaseline is a same-value alias of the pre-existing originalForComparison — harmless but is a redundant name; not fixed since it's cosmetic and out of the "no new behavior" localized-fix scope.

Checks run:
- swift build: clean (only pre-existing CIKernel deprecation warnings, unrelated).
- swift test: 524 passed, 26 expected skips, 0 failures.
- git diff --check (d85409a^..d85409a): clean.
- dg validate: OK (pre-existing runner-model and LUMO-044 context-completeness warnings only).

No blockers found. No child tickets needed. Verification passed — moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T17:07:56.441Z: Independent verification passed: build/tests/diff-check/dg validate all clean, no blockers, no child tickets needed.
