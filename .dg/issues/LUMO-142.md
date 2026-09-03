---
id: LUMO-142
title: Fix black comparison surface when a new unedited photo loads
type: bug
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - bug
  - comparison
  - rendering
  - regression
created: 2026-09-03T01:12:22.879Z
updated: 2026-09-03T01:49:56.240Z
depends_on:
  - LUMO-099
  - LUMO-109
estimate: 3
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-03T01:49:56.237Z
  session: 01MTKV68KH0J6PRG58
---

## Objective

Ensure both sides of Lumo's side-by-side comparison render when the last-used comparison mode is retained and a newly loaded photo has no visible edits.

## Context

Lumo calls this mode “Side by Side” and persists the single-versus-comparison preference independently of the active photo. When that preference survives a photo switch, an identity `EditDocument` still has valid source pixels; the current and comparison panes must both use the settled source/render path rather than treating the lack of visible edits as a missing comparison image. This ticket covers the settled unedited-source case, not the broader thumbnail-switch race tracked separately in LUMO-143.

## Acceptance criteria

- [ ] With the comparison preference enabled, switching to a photo with no saved edits settles with both the source/comparison and current/edited surfaces showing valid pixels; neither surface is black or empty.
- [ ] The result is the same for no edit record, an empty persisted `EditDocument`, and a newly created default document.
- [ ] A transient loading state is allowed, but a settled decode/render failure uses Lumo's existing actionable error state and never masquerades as a black comparison pane.
- [ ] Photos with edits continue to compare correctly, including Reset Photo, Space-hold original, and switching back to single view.
- [ ] Regression coverage asserts the source/render requests and settled presentation state for unedited images while preserving the existing comparison preference across source changes.

## Implementation notes

Audit initialization of the comparison/current render surfaces and their revision gates when `AppViewModel.load` installs a new `ImageSource`. Avoid treating an identity document as “no render output”; the current pane should use the source-derived render until an edit pipeline produces a different result.

## Verification

Add a deterministic regression fixture for an unedited standard image and exercise no-record, empty-record, and default-document cases in single and side-by-side modes. Run the focused comparison tests and full Swift test suite.

## Out of scope

- Reworking comparison-mode UI or changing the user's persisted single/side-by-side preference.
- Fixing rapid thumbnail-selection races or histogram scheduling; those belong to LUMO-143.


### Comment — codex @ 2026-09-03T01:46:15.307Z

Implemented in 9f82307. Side-by-side now remains visible for any installed source when the retained preference is enabled, including identity/default and empty persisted EditDocuments; the comparison baseline uses the same settled source/render path. The active mode remains dismissible after Reset Photo, while the meaningful-edit gate for Space comparison is unchanged. Added deterministic generated-gradient coverage for no-record, empty-record, source-switch, both-surface settled presentation, identity render requests, and reset behavior. Verification: swift test (649 executed, 14 skipped, 0 failures), focused comparison/preview/adjustment/keyboard suites, dg validate OK, git diff --check OK.


### Comment — claude @ 2026-09-03T01:49:53.207Z

## Counterpoint verification — LUMO-142

**Verdict:** PASS

**Scope reviewed:** commit 9f82307 (AppViewModel.swift, ContentView.swift, ComparisonModeTests.swift).

**Correctness:** `isSideBySideVisible` now gates on `sourceImage != nil` instead of `isComparisonAvailable`, so a retained side-by-side preference populates both panes for identity/empty/no-record documents. Traced `install(preparation:)` vs. the decode-failure branch in `prepareAndInstall`: `sourceImage` is only set on the success path, so a settled decode failure still routes to `presentError` and never satisfies `isSideBySideVisible` — no risk of masquerading as a black pane. `toggleSideBySide()` correctly keeps the meaningful-edit gate (`isComparisonAvailable`) for *enabling* comparison from single view, while allowing an already-active retained comparison to remain dismissible (e.g. after Reset Photo). Space-hold comparison (`showOriginal`) and other `isComparisonAvailable` call sites (KeyboardShortcuts, StatusBar, InfoInspectorView "Edited/Original" label) are correctly left untouched — they encode the separate meaningful-edit semantic, not surface availability.

**Maintainability:** Small, localized diff with clear rationale comments explaining why the two gates (`isComparisonAvailable` vs. source availability) are intentionally different now. No new abstractions introduced.

**Security/Performance:** No concerns — no new I/O, no new concurrency surface, no data exposure change.

**Test coverage:** New regression tests cover no-edit-record, empty-persisted-`EditDocument`, and Reset Photo cases in side-by-side mode, asserting both surfaces populate, render requests target the identity document, and the mode remains dismissible. Verified independently:
- `swift build`: clean
- `swift test --filter ComparisonModeTests`: 7/7 passed
- `swift test` (full suite): 649 executed, 14 skipped, 0 failures
- `dg validate`: OK
- `git diff --check` on the commit: clean

No localized fixes were needed; no broader findings warranting a child ticket.

## Agent log

- 2026-09-03T01:49:56.238Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTKV68KH0J6PRG58
