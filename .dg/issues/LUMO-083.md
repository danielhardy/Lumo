---
id: LUMO-083
title: Honor light/dark mode transitions across app background surfaces
type: bug
status: done
priority: high
labels:
  - mvp
  - ux
  - theme
created: 2026-09-01T14:35:33.077Z
updated: 2026-09-01T15:00:57.754Z
order: a0
board: product
commits:
  - 839fc08
---

## Objective

Make the app's background surfaces follow the system light/dark appearance, including a live
transition while the window is open.

## Context

The app can remain visibly dark after macOS switches appearance. Audit the root shell, inspector,
sidebar, library, status, and empty/loading surfaces for hard-coded dark fills or an unintended
color-scheme override. Keep intentionally dark image-analysis surfaces (for example, a histogram
plot) scoped and documented rather than using them as the app-wide background.

## Acceptance criteria

- [ ] Launching in either macOS appearance gives the app a matching background and readable
  primary/secondary text.
- [ ] Switching macOS appearance while the app is open updates the window and all visible app
  surfaces without relaunching.
- [ ] Main shell, inspector, Look browser, library, filmstrip, status bar, empty states, and loading
  states use semantic SwiftUI colors/materials or an equivalent appearance-aware implementation.
- [ ] Intentional dark image content/analysis surfaces remain legible in both appearances and do
  not force their parent containers to stay dark.
- [ ] Add a regression check or documented manual smoke test for launch in both modes and a live
  appearance change.

## Implementation notes

Relevant surfaces include `Sources/LumoKit/Views/ContentView.swift`, `InfoInspectorView.swift`,
`LibraryGridView.swift`, `LUTSidebar.swift`, and `StatusBar.swift`. Avoid changing rendered image
pixels solely to solve window chrome appearance.

### Comment — codex @ 2026-09-01T14:59:28.006Z

Implemented in commit 839fc08. Added centralized appearance-aware window/control surfaces across the shell, preview canvas surround, inspector, Look browser, library, modal, and chart/report UI; preserved intentionally dark histogram, tone-curve, and Metal letterbox analysis surfaces with scoped documentation. Added docs/THEME_VALIDATION.md covering light/dark launch and live transition smoke tests. Verification: swift test — 492 passed, 25 expected skips, 0 failures; swift build and swift build -c release passed; git diff --check passed; dg validate passed with only the pre-existing pickup-runner model warning.

### Comment — claude @ 2026-09-01T15:00:54.554Z

Counterpoint verification (independent, post-human-review): PASS.

Scope check — implementation notes named ContentView, InfoInspectorView, LibraryGridView,
LUTSidebar, StatusBar. Commit 839fc08 covers the first four via a new LumoTheme enum
(windowBackground/controlBackground backed by dynamic NSColor, plus explicitly scoped
analysisBackground/Border/Grid/Reference for the histogram and tone-curve plots) and also
touches PreviewSurface/PreviewView and the recipe extractor/report views, which were in
scope per "background surfaces" even though not explicitly named. StatusBar was not touched
but was already using `.background(.bar)`, a semantic material — no fix needed there.

Verified no forced dark-mode override exists (`preferredColorScheme`/`NSAppearance` grep:
no hits). Grepped remaining Sources/LumoKit/Views for Color.black/.white/.gray/nsColor/
opacity literals: FilmstripView, SourceBrowserView, and StatusBar use only dynamic/semantic
colors (Color.secondary, Color.accentColor, .tertiaryLabelColor, .bar). Only remaining
Color(red:...) literal outside LumoTheme.swift is PreviewSurface's Metal letterbox, which is
documented as an intentional image-presentation surface, matching the acceptance criteria's
carve-out for analysis surfaces.

Reran checks: `swift build` clean, `swift test` — 492 passed, 25 expected skips, 0 failures
(matches the implementer's report). `git diff --check 839fc08^ 839fc08` clean. `dg validate`
OK with only the pre-existing unrelated pickup-runner model warning.

docs/THEME_VALIDATION.md documents the manual smoke test for both launch appearances and a
live transition, satisfying the "regression check or documented manual smoke test"
acceptance criterion (no automated UI test exists for appearance, which is expected for a
SwiftUI/AppKit-appearance concern with no host test harness in this repo).

No blockers, no localized fixes needed, no follow-up tickets warranted — this is a clean,
scoped fix using dynamic AppKit colors correctly. Minor non-blocking nit: LibraryGridView.swift
applies `.background(LumoTheme.windowBackground)` on both the inner ScrollView content and the
outer view (lines 65 and after the closing brace) — harmless (same color, cheap composite) and
not worth a ticket.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T15:00:57.529Z: Independent verification passed: appearance-aware surfaces confirmed across shell, inspector, Look browser, library, and report views; no forced dark-mode override; intentional analysis/presentation dark surfaces correctly scoped and documented; swift build/test clean (492 passed), dg validate OK.
