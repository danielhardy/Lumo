---
id: LUMO-161
title: "main branch fails swift build: AppViewModel/LookSaveCoordinator reference LUTLibrary/CubeLUT APIs never committed"
type: bug
status: backlog
priority: urgent
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - build
created: 2026-09-03T15:08:17.525Z
updated: 2026-09-03T15:08:51.493Z
parent: LUMO-155
order: zzzh
board: product
---

## Objective

Restore a green `swift build` on `main` from a clean checkout — several already-
committed call sites reference APIs that were never committed.

## Context

Found while independently verifying LUMO-155: `scripts/agent-worktree.sh create HEAD`
followed by `swift build` fails with multiple errors, none related to LUMO-155:

- `Sources/LumoKit/ViewModels/AppViewModel.swift:737,750` calls
  `library.importLUT(from:audition:)` — the `audition:` parameter does not exist
  on the committed `LUTLibrary.importLUT`. It only exists in an uncommitted local
  edit to `Sources/LumoKit/Models/LUTLibrary.swift`.
- `Sources/LumoKit/ViewModels/LookSaveCoordinator.swift:115` calls
  `CubeLUT.write(text:to:)` — the committed `CubeLUT.write` only has the
  `write(cube:size:title:to:)` overload; the `text:` overload only exists in an
  uncommitted local edit to `Sources/LumoKit/Models/CubeLUT.swift`.

`git log --oneline -- Sources/LumoKit/ViewModels/LookSaveCoordinator.swift` shows
this call site was committed in `b989c0b` ("LUMO-150: bundle licensed starter
Looks"), i.e. **main has not built from a clean checkout since at least that
commit**, through `c1cb537`, `af88aeb`, `4180292`, `1a8941b`, `ec52625`, and
`d67e322` (LUMO-155). Every "swift build" / "swift test" success claimed in
completion comments across those tickets was necessarily run against a working
tree carrying uncommitted files (`CubeLUT.swift`, `LUTLibrary.swift`,
`LookLUTConverter.swift`, `LumoSettingsView.swift`, `LookSaveSheet.swift`, etc. —
see `git status` at time of writing), not against the actual git history. CI
running from a fresh clone should be failing on this; worth checking why it
hasn't been caught (see also [[LUMO-160]] which found the parallel Settings-UI
gap from the same uncommitted-work situation).

## Acceptance criteria

- [ ] `swift build` succeeds from a fresh `git worktree`/clone of `main` HEAD, with
      no reliance on untracked files.
- [ ] `swift test` succeeds under the same condition.
- [ ] Either commit the missing `LUTLibrary.importLUT(from:audition:)` and
      `CubeLUT.write(text:to:)` APIs (if that work is finished/reviewed), or revert
      the call sites that reference them until that work lands.
- [ ] Confirm why CI did not catch a broken `main` across the last several merges.

## Implementation notes

This is almost certainly the same in-flight Look/LUT "Save as Look/LUT…" feature
referenced in [[LUMO-160]] — the fix is likely to land as part of committing that
work properly rather than as an isolated revert, but flag to a human either way
since it affects every ticket currently building against `main`.
