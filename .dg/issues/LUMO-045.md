---
id: LUMO-045
title: Build the Library/Edit navigation shell and image-centric layout
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:editor
  - phase:8
created: 2026-08-30T18:30:32.194Z
updated: 2026-09-01T16:40:52.699Z
depends_on:
  - LUMO-021
  - LUMO-007
estimate: 5
order: a0
board: product
commits:
  - "7e33737"
---

## Objective

Create explicit Grid and Edit modes using the target sidebar/canvas/inspector/filmstrip structure without a giant view-model rewrite.

## Context

Part of **Epic 8 — Image-centric editor experience**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Model navigation state separately from library, edit, and render state.
- Compose existing LUT, metadata, histogram, preview, and filmstrip features into the new shell incrementally.
- Provide G, E, Enter, and obvious toolbar navigation.
- Maintain a large uninterrupted canvas at normal window sizes.

## Acceptance criteria

- [ ] Grid and Edit modes have deterministic navigation and selection handoff.
- [ ] Normal editing requires no modal dialog.
- [ ] Existing import, derive, inspector, and export entry points remain reachable.
- [ ] Layout handles supported minimum window size without overlapping controls.

## Verification

- Add navigation-state tests and manual window-size regression checks.

## Out of scope

- Album management.
- A visual clone of Lightroom.

### Comment — codex @ 2026-09-01T16:37:36.959Z

Implemented in commit 72aad2c. Added an explicit NavigationState with deterministic Grid/Edit transitions, active-photo selection handoff, Library/Edit toolbar navigation, G/E/Enter keyboard routes, and Source-sidebar routing. Preserved existing LUT, metadata, histogram, preview, filmstrip, import, derive, and export surfaces. Added NavigationStateTests and WorkspaceNavigationTests. Verification: swift test (514 passed, 26 expected skips), swift build -c release passed, git diff --check passed, dg validate passed with only known runner-model and unrelated LUMO-044 context warnings. Interactive window resize was unavailable because the Swift Package executable was not exposed to the desktop accessibility bridge; the source retains the existing 800x500 minimum and the shell has no overlapping layout changes.

### Comment — claude @ 2026-09-01T16:40:50.272Z

Counterpoint verification (independent, post-human-review): PASS with one localized fix applied.

Reviewed commit 72aad2c against the acceptance criteria and re-ran the declared checks:
- swift build: clean.
- swift test: 514 passed, 26 expected skips (includes NavigationStateTests and WorkspaceNavigationTests).
- swift build -c release: clean.
- git diff --check: clean.

Findings:
- Traced the loadMode:false path through openActiveCollectionImage(_:) suspecting a missed navigation.move(.edit) for collection items backed by imageData (no file URL). Confirmed not a bug: navigate(to: .edit) already sets navigation.move(to: .edit) itself before calling into openActiveCollectionImage, so the data-only path is covered.
- Confirmed openFirstImageWhenScanned() deliberately calls load(...) directly instead of openImage(url:) so the initial folder scan doesn't flip navigation from .grid back to .edit — correct, not a regression.
- Found isLibraryGridPresented (AppViewModel.swift) was a dead compatibility seam: grep across Sources/ and Tests/ showed no remaining callers after ContentView.swift and KeyboardShortcuts.swift were migrated to navigation.isGrid / navigate(to:). Its setter also bypassed the collection-active guard and beginThumbnailDemand() policy that navigate(to:) applies, so it was a latent trap for any future caller. Removed it as a localized, no-behavior-change cleanup (commit 7e33737). Rebuilt and re-ran the full suite after removal: still 514 passed / 26 skipped, release build clean.

No blockers found. Acceptance criteria (deterministic Grid/Edit navigation and selection handoff, no modal for normal editing, import/derive/inspector/export entry points reachable) verified by reading call sites; the toolbar Picker degrades safely (silent no-op) when navigate(to:) returns false for an inactive collection. Window-resize/overlap check remains manual-only per the implementer's note (Swift Package executable not exposed to the accessibility bridge) — the toolbar addition is a standard SwiftUI .toolbar item, which macOS overflows into a chevron menu rather than clipping, so this is low risk but still worth a human eyeball at the 800x500 minimum next time the app runs interactively.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T16:40:52.697Z: Independent verification passed; removed dead isLibraryGridPresented compat seam as a localized fix. 514 tests pass, release build clean.
