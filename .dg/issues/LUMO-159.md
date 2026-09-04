---
id: LUMO-159
title: Opening a second image leaves the app stuck on the loading spinner
type: bug
status: done
priority: high
labels:
  - loading
  - preview
  - image-switching
  - lifecycle
  - verification
created: 2026-09-03T15:06:01.276Z
updated: 2026-09-03T16:11:53.325Z
order: t
board: product
commits:
  - deaa14d
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Sequential replacement preview completes without an unrelated user action and leaves loading state
      result: pass
    - criterion: Preview surfaces are directly observed while loading, so new source frames trigger view construction and drawable presentation
      result: pass
    - criterion: Existing source revision, cancellation, failure, comparison, and persistence behavior remains covered by the existing lifecycle suites
      result: pass
    - criterion: Gated fake-renderer regression covers the second preview and terminal ready state
      result: pass
  checks_run:
    - swift test --filter ThumbnailSwitchLifecycleTests
    - swift test (708 tests, 0 failures, 14 expected skips)
    - swift build -c release
    - git diff --check
    - dg validate
  findings: []
  fixes: []
  verification_commits:
    - deaa14d
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-03T16:11:53.319Z
  session: 01MTLPQCPLHW56EKD1
---

## Objective

Ensure opening a new image after one is already displayed completes the source and
preview lifecycle without requiring an unrelated user interaction.

## Context

Open image A and wait for it to render. Then open or select image B. Lumo switches to
a loading spinner and can remain there indefinitely; clicking around in the window
(for example, another control or the canvas) eventually causes the new image to
appear. The second open therefore appears hung even though a later UI action can
unstick it.

The first-image path can work while the replacement path fails, so this should be
treated as a source-switch/render-lifecycle defect rather than only a spinner styling
issue. Relevant code is in the `load`/`install` source lifecycle in
`Sources/LumoKit/ViewModels/AppViewModel.swift`, preview scheduling/publication in
`Sources/LumoKit/ViewModels/PreviewCoordinator.swift`, and loading-state rendering
in `Sources/LumoKit/Views/PreviewView.swift`.

## Acceptance criteria

- [ ] After image A is ready, opening image B automatically reaches a terminal state
      and displays B's preview without any click, zoom, edit, or other user action.
- [ ] The replacement path clears the old image intentionally, shows loading only
      while B is actually preparing/rendering, and publishes B's source, preview, and
      status in the correct order.
- [ ] Successful loads leave the spinner and loading flags; preparation or render
      failures leave a useful error state instead of an indefinite spinner.
- [ ] Repeated and rapid switches (A → B → C, including selecting the current image
      again) cannot deadlock the worker or allow obsolete source/preview results to
      overwrite the latest selection.
- [ ] Existing first-open behavior, persisted per-photo edits, side-by-side/original
      comparison surfaces, and loading cancellation remain correct.
- [ ] Add regression coverage that opens at least two distinct images sequentially
      with a controllable/fake renderer, waits for the second preview without driving
      another action, and covers stale completion/cancellation and failure paths.

## Implementation notes

Trace the replaceable source-load request, `sourceRevision` guards, coordinator cancellation,
surface clearing, and `previewState`/`isLoading` transitions as one state machine. Preserve
the generation checks that prevent late work from publishing into a different photo, but
ensure the current request is always pumped after the previous request finishes or is
cancelled. The fix must not depend on a SwiftUI body refresh caused by clicking another
control and must not make source switching mutate edit history.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-03T16:11:53.322Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Sequential replacement preview completes without an unrelated user action and leaves loading state (pass)
- [x] Preview surfaces are directly observed while loading, so new source frames trigger view construction and drawable presentation (pass)
- [x] Existing source revision, cancellation, failure, comparison, and persistence behavior remains covered by the existing lifecycle suites (pass)
- [x] Gated fake-renderer regression covers the second preview and terminal ready state (pass)
Checks run:
- swift test --filter ThumbnailSwitchLifecycleTests
- swift test (708 tests, 0 failures, 14 expected skips)
- swift build -c release
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- deaa14d
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTLPQCPLHW56EKD1
Summary: Keep PreviewView subscribed to the main and comparison preview surfaces while loading so completed replacement renders trigger the canvas lifecycle; add gated sequential A-to-B regression coverage.
