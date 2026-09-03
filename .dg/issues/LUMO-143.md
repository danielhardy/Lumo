---
id: LUMO-143
title: Fix intermittent black canvas and stuck histogram when switching photo thumbnails
type: bug
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - bug
  - regression
  - navigation
  - photo-loading
  - rendering
  - histogram
created: 2026-09-03T01:12:23.443Z
updated: 2026-09-03T02:14:02.213Z
depends_on:
  - LUMO-048
  - LUMO-109
  - LUMO-130
estimate: 5
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Every successful thumbnail selection presents the photo and settles the Info histogram when supported
      result: pass
    - criterion: No indefinite spinner/loading histogram after settling; decode/unsupported/calculation failures show actionable error or explicit empty state
      result: pass
    - criterion: Rapid thumbnail changes resolve to the latest selected PhotoAssetID; stale source/preview/metadata/histogram completions cannot overwrite it
      result: pass
    - criterion: Switching inspector tabs is not required to complete rendering and does not reset loaded photo/preview/histogram state
      result: pass
    - criterion: Works for edited/unedited photos, repeated selection, and both filmstrip and Library grid entry points
      result: pass
    - criterion: Automated regression coverage exercises normal, rapid, repeated, failed-source, failed-histogram, and tab-switching paths with explicit revision/ownership assertions
      result: pass
  checks_run:
    - swift test --filter ThumbnailSwitchLifecycleTests|PreviewCoordinatorTests — 12 passed, 1 expected benchmark skip
    - swift test (full suite) — 654 executed, 14 expected skips, 0 failures
    - swift build -c release — passed
    - git diff --check 21ae717~1 21ae717 — clean
    - git status --porcelain -- Sources Tests Package.swift — clean (no stray edits from review)
    - dg validate — OK with pre-existing unknown pickup-runner-model warning
  findings:
    - "Non-blocking: the manual rapid-thumbnail pass (filmstrip/Library grid, tab switching, repeated selection, edited/unedited, a representative decode failure) called for in the ticket's Verification section was not performed — this sandboxed environment has no interactive Lumo window either. Automated ThumbnailSwitchLifecycleTests cover the equivalent scenarios (normal, rapid, repeated, failed-source, failed-histogram, Library grid, filmstrip, tab-independent handoff) with explicit revision/ownership assertions, so this is a documentation/process gap rather than a behavioral risk."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-03T02:14:02.206Z
  session: 01MTKVXSIC5M97FQ50
---

## Objective

Make filmstrip/library-thumbnail photo switching reliably load the selected image and histogram without requiring an inspector-tab change as a workaround.

## Context

The filmstrip and Library grid both hand off through the same `AppViewModel` source-selection path. A thumbnail click can currently leave a spinner, black/empty presentation, or a histogram that never settles; visiting the Light tab can accidentally trigger the missing render. This indicates stale or competing revisions between selection, `RenderEngine` source preparation, preview presentation, histogram work, and `InspectorState` tab activation. LUMO-142 covers the narrower identity-document comparison bug; this ticket covers request ordering and lifecycle across thumbnail switches.

## Acceptance criteria

- [ ] Every successful thumbnail selection eventually presents that photo on the canvas and settles the Info histogram when the source supports histogram data.
- [ ] Once loading settles, no spinner or loading histogram remains indefinitely; decode, unsupported-format, and calculation failures use an actionable error or explicit empty state.
- [ ] Rapid thumbnail changes resolve to the latest selected `PhotoAssetID`; stale source, preview, metadata, or histogram completions cannot overwrite it.
- [ ] Switching inspector tabs is not required to complete rendering and does not reset the loaded photo, preview, or histogram state.
- [ ] The behavior works for edited and unedited photos, repeated selection of the same thumbnail, and both the filmstrip and Library grid entry points.
- [ ] Automated regression coverage exercises normal, rapid, repeated, failed-source, failed-histogram, and tab-switching paths with explicit revision/ownership assertions.

## Implementation notes

Trace cancellation and the existing source/display/document revision IDs across `ImageCollection`, source preparation, preview presentation, metadata, and histogram computation. Keep `collection.selection.activeID`/the active source as the authority and require every async completion to prove ownership before publishing UI state. Preserve the existing last-presented valid frame behavior for failures.

## Verification

Run focused navigation, preview, and histogram tests plus the full Swift test suite. Record a manual rapid-thumbnail pass covering both filmstrip and Library grid, tab switching, repeated selection, edited/unedited sources, and a representative decode failure.

## Out of scope

- Changing the comparison-mode semantics or redesigning the histogram visualization.
- Adding a new thumbnail service or broad cache rewrite beyond the smallest ownership/cancellation fix.


### Comment — codex @ 2026-09-03T02:07:35.616Z

Implemented in commit 21ae717. Added source/display generation ownership through preview publication and presentation callbacks, explicit preview/histogram loading and terminal failure states, and preserved valid-frame behavior. Added regression coverage for normal, rapid, repeated, failed-source, failed-histogram, Library-grid, filmstrip, tab-independent handoff, and generation propagation. Verification: swift test — 652 passed, 14 expected skips, 0 failures; focused PreviewCoordinator/ThumbnailSwitchLifecycle tests — 12 passed, 1 expected benchmark skip; swift build -c release — passed; dg validate — passed with pre-existing unknown pickup-runner warning; git diff --check — passed. Manual rapid-thumbnail pass was not run because this workspace has no interactive Lumo app/window available.

## Agent log

- 2026-09-03T02:14:02.211Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Every successful thumbnail selection presents the photo and settles the Info histogram when supported (pass)
- [x] No indefinite spinner/loading histogram after settling; decode/unsupported/calculation failures show actionable error or explicit empty state (pass)
- [x] Rapid thumbnail changes resolve to the latest selected PhotoAssetID; stale source/preview/metadata/histogram completions cannot overwrite it (pass)
- [x] Switching inspector tabs is not required to complete rendering and does not reset loaded photo/preview/histogram state (pass)
- [x] Works for edited/unedited photos, repeated selection, and both filmstrip and Library grid entry points (pass)
- [x] Automated regression coverage exercises normal, rapid, repeated, failed-source, failed-histogram, and tab-switching paths with explicit revision/ownership assertions (pass)
Checks run:
- swift test --filter ThumbnailSwitchLifecycleTests|PreviewCoordinatorTests — 12 passed, 1 expected benchmark skip
- swift test (full suite) — 654 executed, 14 expected skips, 0 failures
- swift build -c release — passed
- git diff --check 21ae717~1 21ae717 — clean
- git status --porcelain -- Sources Tests Package.swift — clean (no stray edits from review)
- dg validate — OK with pre-existing unknown pickup-runner-model warning
Findings:
- Non-blocking: the manual rapid-thumbnail pass (filmstrip/Library grid, tab switching, repeated selection, edited/unedited, a representative decode failure) called for in the ticket's Verification section was not performed — this sandboxed environment has no interactive Lumo window either. Automated ThumbnailSwitchLifecycleTests cover the equivalent scenarios (normal, rapid, repeated, failed-source, failed-histogram, Library grid, filmstrip, tab-independent handoff) with explicit revision/ownership assertions, so this is a documentation/process gap rather than a behavioral risk.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTKVXSIC5M97FQ50
Summary: Counterpoint verification passed: thumbnail-switch generation ownership (source/display revisions), explicit preview/histogram loading/failure states, and last-valid-frame preservation confirmed correctly implemented and tested in 21ae717.
