---
id: LUMO-085
title: Consolidate Look and LUT into one optional Look stage and sidebar surface
type: task
status: done
priority: high
labels:
  - mvp
  - ux
  - epic:lut
created: 2026-09-01T14:35:33.676Z
updated: 2026-09-01T15:23:55.472Z
order: a0
board: product
commits:
  - 47b08b9
---

## Objective

Give the user one canonical optional Look stage and one browser surface instead of separate Look
and LUT concepts/locations.

## Context

The product language is now Look, while the implementation still exposes LUT terminology and the
user sees Look in the right inspector alongside a separate LUT area on the left. Consolidate the
navigation and controls without losing the underlying `.cube` LUT behavior: selection, intensity,
None, missing-file reporting, folder search, auditioning, derive, reset, persistence, undo, and
copy/paste must all continue to operate on the same per-photo Look state.

## Acceptance criteria

- [x] There is one visible, discoverable Look browser; no duplicate Look/LUT browser or competing
  selection/intensity controls remain in the normal editing workflow.
- [x] The single surface provides folder scanning, search, None, selection, intensity, derive, and
  reset actions with consistent Look terminology.
- [x] Existing per-photo selection and intensity survive navigation and relaunch, including an
  unresolved/missing LUT reference and explicit None.
- [x] Preview, export, undo, copy/paste, keyboard auditioning, and missing-file messaging use the
  same canonical Look state after consolidation.
- [x] Remove or migrate obsolete entry points and add navigation/regression coverage proving there
  is only one authoritative surface.

## Implementation notes

Relevant code: `Sources/LumoKit/Views/InfoInspectorView.swift`,
`Sources/LumoKit/Views/LUTSidebar.swift`, `AppViewModel` Look/LUT state, and menu/keyboard routing.
Do not rename persisted LUT identifiers or delete the `.cube` model merely to change product
terminology.

### Comment — codex @ 2026-09-01T15:21:41.814Z

Implemented in commit 47b08b9. Consolidated the editor workflow around one canonical Look browser: renamed LUTSidebar.swift to LookInspectorView.swift, added direct Look toolbar navigation into the shared inspector tab, routed selection/intensity/audition/folder actions through Look-named AppViewModel APIs, and removed user-facing LUT terminology from menus, missing-file status, derive/save UI, preview/status surfaces, and README. Persisted LUTID/LUTSettings/.cube behavior remains unchanged. Added regression coverage for shared Look navigation, missing-reference vs explicit None, Look intensity, library audition, navigation/relaunch, and the canonical menu route. Verification: swift test — 500 passed, 26 expected skips; swift build -c release — passed; git diff --check — passed; dg validate — passed with only the pre-existing unknown pickup-runner warning.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

### Verification — claude @ 2026-09-01T15:22:02.531Z

Independent counterpoint review of commit 47b08b9, no code changes needed (pass).

- Reproduced all claimed checks from a clean tree: `swift build` clean; `swift test` → 500 passed,
  26 skipped, 0 failures; `swift build -c release` clean; `git diff --check 47b08b9~1 47b08b9` clean;
  `dg validate` → OK (only the pre-existing unrelated pickup-runner model warning).
- Confirmed single surface: `ContentView` mounts one `InfoInspectorView`, which switches on
  `inspectorTab` and hosts `LookInspectorView` (renamed from `LUTSidebar.swift`) as its only Look
  tab — no second left-side LUT panel remains. New toolbar button routes through
  `AppViewModel.showLookInspector()` into the same tab; a dedicated test
  (`testLookNavigationOpensTheSingleAuthoritativeInspectorSurface`) pins this.
- Confirmed the persisted model is untouched: `document.lut.lutID` / `document.lut.intensity` are
  read/written in exactly the same places as before (`AppViewModel.swift`); only the
  view-model-level API was renamed to Look-named methods (`selectLook`, `setLookIntensity`,
  `chooseLookFolder`, `selectPreviousLook`/`selectNextLook`), satisfying "do not rename persisted
  LUT identifiers."
- Old-named methods (`selectLUT`, `setLUTIntensity`, `chooseLUTFolder`, `selectPreviousLUT`/
  `selectNextLUT`) are kept as one-line compatibility shims. Verified via grep that no code under
  `Sources/` calls the old names anymore — every call site there uses the new Look-named API. The
  shims exist solely because a large body of pre-existing tests
  (`AppViewModelTests`, `AdjustInspectorTests`, `DevelopInspectorTests`, `ExportCutoverTests`,
  `PreviewCutoverTests` — none touched by this change) still reference the old names; keeping them
  as thin shims rather than mass-renaming those files is appropriately scoped, not a leftover
  duplicate surface.
- No remaining user-facing "LUT" terminology in `Sources/LumoKit/Views/` (menus, status messages,
  derive/save sheet, preview badges, README) beyond internal comments/identifiers, which the issue
  explicitly allows.
- New regression tests (`LUTWorkflowTests`, `MenuCommandTests`) cover: single-inspector-tab
  navigation, missing-reference vs. explicit-None distinction, intensity persistence across None,
  audition order via the library, and the canonical menu Notification name — matching each
  acceptance criterion.
- No blockers found. No child tickets created. Acceptance criteria checked off above.

Verdict: **pass** — moving to `done`, clearing lease.

- 2026-09-01T15:23:55.470Z: Independent verification pass: reproduced swift test (500 passed/26 skipped), release build, git diff --check, and dg validate; confirmed single Look inspector surface, persisted LUTID/intensity model untouched, and old-named APIs are unused shims. No blockers.
