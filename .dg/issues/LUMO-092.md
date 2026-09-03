---
id: LUMO-092
title: Show the Develop tab only for images with supported develop functionality
type: task
status: done
priority: high
labels:
  - mvp
  - raw
  - ux
created: 2026-09-01T14:35:35.746Z
updated: 2026-09-01T15:40:35.955Z
order: zzzzv
board: product
commits:
  - 25093a7
---

## Objective

Show the Develop inspector tab only when the selected image actually has usable RAW develop
functionality.

## Context

The inspector tab picker is built from all `InspectorTab` cases, so standard images can expose a
Develop tab whose content says “No develop stage.” The app already probes RAW capabilities and
distinguishes probing from no stage; that state should drive tab availability as well as panel
content. “RAW” alone may not be enough if a decoder reports no actionable controls.

## Acceptance criteria

- [ ] Standard/non-RAW images do not show a Develop tab in the inspector switcher.
- [ ] RAW images show the tab while capability probing is in flight, with an honest loading state,
  and retain it only when the selected decoder offers at least the supported develop functionality
  the panel can edit.
- [ ] Changing selection between RAW and non-RAW images updates tab availability immediately and
  never leaves the inspector showing the previous image's Develop content.
- [ ] If the active tab becomes unavailable, selection falls back to a valid tab without a blank
  panel or unexpected data mutation.
- [ ] Add state-mapping and navigation coverage for no image, standard image, probing RAW, RAW with
  supported controls, and RAW with no actionable supported controls.

## Implementation notes

Relevant seams: `AppViewModel.InspectorTab`, `developPanelState`, `RAWCapabilities.availableControls`,
`InfoInspectorView.tabSwitcher`, and navigation/load publication. Keep the distinction between
“capabilities are still probing” and “no develop stage” explicit and testable.

### Comment — codex @ 2026-09-01T15:37:31.888Z

Implemented and committed as 771ff51. Develop now derives from RAW capability probe state: standard/no-image sources hide the tab, RAW probing keeps it visible with loading state, and completed decoders with no actionable controls remove it. Selection falls back to Info when Develop becomes unavailable, with source publication ordered to avoid stale-image state. Added mapping and navigation regressions. Verification: swift test (505 passed, 26 expected RAW-environment skips), swift build -c release, git diff --check, dg validate; all passed.

### Comment — claude @ 2026-09-01T15:40:32.604Z

## Verification report (counterpoint, independent of author)

**Scope reviewed:** commit 771ff51 (AppViewModel.swift, DevelopInspectorView.swift, InfoInspectorView.swift, DevelopInspectorTests.swift).

**Correctness**
- Traced all mutation sites of `sourceImage`/`imageSource`/`rawCapabilities`/`capabilitiesProbeCompleted` (openImage top-of-function reset, openImage success, refreshCapabilities both branches) — every one is followed by `keepInspectorTabValid()`, so the Picker's `ForEach(viewModel.availableInspectorTabs)` can never carry a stale `inspectorTab` selection outside the list SwiftUI is given.
- Confirmed ordering in `openImage`: `imageSource` is set before `sourceImage`/`sourceURL`/etc, and `keepInspectorTabValid()` runs before `refreshCapabilities()` kicks the async probe — so a freshly opened RAW shows `.probing` (Develop tab present, honest loading state) with no window where it briefly reads `.noDevelopStage`.
- Verified the stale-probe guard: `openImage` clears `imageSource = nil` synchronously before decoding, so an in-flight `capabilitiesTask` from the previous image fails its `self.imageSource == imageSource` check and cannot apply a stale answer to the new source.
- `DevelopPanelState(sourceIsRAW:capabilities:probeCompleted:)` mapping checked by hand against all reachable input combinations; matches `.probing` / `.ready` / `.noSupportedControls` / `.noDevelopStage` as intended. `InspectorTab.availableTabs` correctly filters only `.develop` on `offersDevelopTab`.
- No blank-panel path found: on decode failure, `keepInspectorTabValid()` had already run at the top of `openImage` (before the async decode), consistent with "no image" state.

**Checks run (independently, not reused from author's report)**
- `swift build` — clean.
- `swift build -c release` — clean.
- `swift test` — 505 passed, 26 skipped (expected RAW-environment skips, no local DNG), 0 failures. Matches author's reported counts.
- `swift test --filter DevelopInspectorTests` — 31 passed, 2 skipped, 0 failures.
- `git diff --check` on the commit — clean.

**Finding (fixed in this pass, localized doc-only change)**
The header comment above `DevelopInspectorView` had its sentence severed mid-edit: "...on every ←/→ step through a folder of them, since\n/// The active tab is repaired..." — a dangling "since" followed by a new capitalized sentence, and the doc still said "Three states" after a fourth (`.noSupportedControls`) was added. No behavior change; fixed directly (commit 25093a7) since it was a pure comment correction, not a product/API change.

**Maintainability/test-coverage note (non-blocking, no ticket needed)**
The `.noSupportedControls` end-to-end path (a real RAW decoder that answers with zero actionable controls) is only covered by the synthetic `DevelopPanelState` initializer test, not through `AppViewModel` + `FakeRenderEngine` end-to-end, because `openStandardImage` opens a non-RAW fixture. This mirrors the existing CI constraint (no local DNG) already documented on `testARAWStaysOnProbingUntilTheProbeAnswers`, and `FakeRenderEngine` could stub `imageSource.kind == .raw` for a non-DNG fixture to close this gap in a future pass. Not filing a child ticket — small enough to fold into any future touch of this test file.

**Verdict: PASS.** No blockers. Issue moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T15:40:35.693Z: Independent verification passed: build/tests/release all green, matches author's report. Fixed a broken doc comment (severed sentence, stale state count) in DevelopInspectorView.swift as a localized follow-up.
