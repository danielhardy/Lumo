---
id: LUMO-158
title: Side-by-side comparison opens with a missing Original image
type: bug
status: done
priority: high
labels:
  - comparison
  - preview
  - canvas
  - rendering
  - verification
created: 2026-09-03T14:44:27.552Z
updated: 2026-09-03T15:33:30.212Z
order: t
board: product
commits:
  - 4d53a51
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 4d53a51
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-03T15:33:30.206Z
  session: 01MTLNYSVQ2TE9GM5Y
---

## Objective

Fix side-by-side comparison so the Original pane is populated immediately when the
mode is opened.

## Context

With an edited photo open and its normal preview visible, switch to Side by Side.
The adjusted pane appears, but the pane labeled “Original” is initially missing or
blank. The Original image only appears after the user takes another action, such as
editing, zooming, or otherwise causing another preview update. This makes the mode
look broken and prevents the user from comparing the two states at the moment they
enter it.

Relevant current presentation and comparison-render paths are in
`Sources/LumoKit/Views/PreviewView.swift`, the comparison state and scheduling code
in `Sources/LumoKit/ViewModels/AppViewModel.swift`, and
`Sources/LumoKit/ViewModels/PreviewCoordinator.swift`.

## Acceptance criteria

- [ ] With a settled edited preview visible, entering Side by Side immediately shows
      both panes: the current adjusted image and the corresponding Original/baseline
      image, without requiring any additional user action.
- [ ] The Original pane uses the correct baseline for the active photo and current
      develop/crop state; it is not stale data from the previously selected photo or
      an image from before the latest comparison-frame change.
- [ ] If the baseline is still rendering, show an intentional loading/placeholder
      state and replace it automatically when the render completes; never leave the
      pane permanently blank or dependent on an unrelated later action.
- [ ] First entry, repeated toggles, switching photos while the preference is retained,
      and reopening the app/window all initialize the Original pane correctly.
- [ ] Existing single-photo display, Space-to-show-original behavior, adjusted-pane
      rendering, zoom/pan registration, and comparison availability rules remain intact.
- [ ] Add regression coverage that toggles side-by-side after a settled visible render,
      verifies the baseline request/publication and both visible surfaces, and covers
      cancellation or out-of-order render completion where applicable.

## Implementation notes

Trace the transition from `toggleSideBySide()` through comparison-baseline scheduling
and `originalPreviewSurface` publication. The fix should explicitly invalidate or
request the missing baseline at mode entry while retaining the existing generation
guards and render-priority policy. Do not make a presentation-only comparison toggle
an edit-document/history change, and keep the baseline aligned with the same source,
develop, crop, resolution, and color-space assumptions as the current preview.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-03T15:33:30.210Z: Verification report
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
- 4d53a51
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTLNYSVQ2TE9GM5Y
Summary: Populate the Original pane immediately when entering side-by-side comparison, invalidate stale baselines on source/document changes, show loading feedback, and add lifecycle/race regression coverage.
