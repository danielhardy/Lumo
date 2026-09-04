---
id: LUMO-178
title: Open Image… allows selecting multiple images
type: feature
status: done
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - multi-select
created: 2026-09-04T13:26:37.174Z
updated: 2026-09-04T13:40:06.196Z
order: a0
board: product
commits:
  - f4e5593
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: openImageDialog() sets panel.allowsMultipleSelection = true.
      result: pass
      notes: AppViewModel.swift:1178.
    - criterion: On .OK with one or more panel.urls, every selected file is added as a URL-backed PhotoAsset (no Data decode), collection is cleared then repopulated.
      result: pass
      notes: ImageCollection.addFromURLs(_:) calls clear() then constructs each PhotoAsset from the URL only (metadata + bookmark data), never reading file bytes into Data; mirrors addFromMediaVolume's URL-backed construction.
    - criterion: Editing navigates to .edit and loads (renders) the first selected image; the rest remain in the library for navigation.
      result: pass
      notes: "openImages(urls:) loads collection.items.first(where: id == firstID) via openImage(url:assetID:), which calls navigation.move(to: .edit); remaining items stay in collection.items."
    - criterion: A bare single-selection keeps working exactly as today (no regression for the one-file case).
      result: pass
      notes: Covered by testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs; single-URL path produces one item and loads it as before.
    - criterion: Cancelled dialog (.cancel) leaves the collection and current edit untouched.
      result: pass
      notes: openImages(urls:) is only called inside the panel.runModal() == .OK branch, so a cancel never touches the collection or editor state.
    - criterion: Preserve ordering (sort by path) and duplicate/identity handling consistent with the rest of the importer.
      result: pass
      notes: addFromURLs sorts by standardizedFileURL.path with localizedStandardCompare (matches addFromMediaVolume) and dedups via Set<PhotoAssetID>, recording a scan warning for duplicates/unreadable files.
    - criterion: "Swift 6 clean: no new Sendable/escape hatches."
      result: pass
      notes: Diff is synchronous MainActor UI code; no @unchecked Sendable, nonisolated(unsafe), or @preconcurrency introduced.
    - criterion: Unit tests cover multi-select, single-file, dedup, and cancellation; swift test stays green.
      result: pass
      notes: "Tests/LumoKitTests/OpenImageDialogTests.swift covers sorted multi-open, single-file/dedup, and empty-selection (cancel-equivalent) leaving state untouched. Re-ran: swift test --filter OpenImageDialogTests (3 passed) and full swift test (748 passed, 34 expected skips, 0 failures)."
  checks_run:
    - swift test --filter OpenImageDialogTests (3 passed, 0 failed)
    - swift test (748 passed, 34 expected skips, 0 failures)
    - git diff --check f4e5593~1 f4e5593 (clean)
  findings:
    - "Non-blocking (filed LUMO-180, verification label, parent LUMO-178): ImageCollection.addFromURLs(_:) duplicates most of addFromMediaVolume(_:files:)'s sort/read/dedup/append loop almost verbatim; worth factoring into a shared helper, but out of scope as a localized fix for this ticket."
  fixes: []
  verification_commits:
    - f4e5593
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T13:40:06.192Z
  session: 01MTMZXINA894HG05U
---

**Type:** Feature
**Component:** `LumoKit/ViewModels/AppViewModel.swift` — `openImageDialog()`
**Depends on:** none

## 1. Problem

The *"Open Image…"* entry (menu, toolbar, and `ContentView` drop all funnel through
`AppViewModel.openImageDialog()`) shows an `NSOpenPanel` with `allowsMultipleSelection = false`, so
the user can only ever pick one file. On OK it calls `collection.clear()` and opens that single URL
via `openImage(url:)`, replacing the whole library with one photo.

Users expect a file open dialog to let them select several files at once (Cmd-click / Shift-click)
and import all of them — not be forced to repeat *Open Image…* for every photo.

## 2. Requirement (acceptance criteria)

1. `openImageDialog()` sets `panel.allowsMultipleSelection = true`.
2. On `.OK` with **one or more** `panel.urls`:
   - every selected file is added to the collection as a **URL-backed** `PhotoAsset` (NOT decoded
     into `Data`), so RAW demosaicing stays renderer-owned and happens at preview scale, exactly as
     it does for the single-image path (`openImage(url:)` / `load(...)` with a URL and no `data`).
   - the collection is cleared first, then repopulated with the selected files.
   - editing navigates to `.edit` and **loads (renders) the first** selected image; the rest are
     available in the library for navigation.
3. A bare single-selection keeps working exactly as today (one asset, editor shows it) — no
   behavioural regression for the one-file case.
4. Cancelled dialog (`.cancel`) leaves the collection and current edit untouched.

## 3. Implementation notes / guidance

- **Keep it URL-backed.** Do not read file bytes into `Data` for multi-open. The single path is
  `openImage(url:) → load(name:url:data: nil, assetID: nil)`; multi-open should add each URL as an
  item and then `load(...)` the first one — mirroring `importPhotosData(_:)`'s structure
  (add all, then load the first) but with file URLs instead of `Data` payloads.
- Check whether a collection helper already turns URL-backed files into items (see
  `ImageCollection.addFromMediaVolume(_:files:)` and `addFromData(_:)`); prefer reusing a URL-path
  variant rather than inventing a new asset-construction path. If none exists, add one that builds
  `PhotoAsset`s from file URLs with metadata + bookmark data, matching the removable-media path.
- Preserve ordering (sort by path) and duplicate/identity handling consistent with the rest of the
  importer.
- Keep it Swift 6 clean: this is synchronous UI handling, no `Sendable` concerns beyond what
  `openImage(url:)` already has.

## 4. Where to look

- `Sources/LumoKit/ViewModels/AppViewModel.swift`
  - `openImageDialog()` (line ~1175) — the one to change.
  - `openImage(url:)` / `load(...)` (lines ~923–960) — single-image reference behaviour.
  - `importPhotosData(_:)` (line ~1276) — "add all, then load first" shape.
- `Sources/LumoKit/Models/ImageCollection.swift` — `addFromMediaVolume(_:files:)`, `addFromData(_:)`.
- `Sources/LumoKit/Views/MenuCommands.swift` (line ~29, 103) — command entry points.

## 5. Testing

- Unit test `openImageDialog()` selection handling: assert that with multiple `.OK` URLs the
  collection ends up with each URL as an item and the editor is left on the first. Cover the
  single-file case, the empty-selection edge (all same file — dedup), and cancellation.
- Existing tests must stay green (`swift test`); no new `@unchecked Sendable` / escape hatches.

---
Ported from a spec drafted by another AI session as `docs/LUMO-177-open-multiple-images.md`,
which was never registered as a real dg ticket (no `dg issue create` was run). Re-filed here as
LUMO-178 since LUMO-177 was already taken by an unrelated ticket.


### Comment — codex @ 2026-09-04T13:34:55.625Z

Implemented in commit f4e5593. Open Image… now enables multi-selection, imports sorted/deduplicated URL-backed PhotoAssets with metadata/bookmarks, clears and repopulates the collection, and loads the first asset in edit mode. Empty/cancel results leave the current edit untouched. Added focused multi/single/dedup/cancel coverage. Verification: swift test --filter OpenImageDialogTests (3 passed); swift test (748 passed, 34 expected skips, 0 failures); dg validate (OK with pre-existing unknown pickup-runner/context warnings); git diff --check passed.

## Agent log

- 2026-09-04T13:40:06.194Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] openImageDialog() sets panel.allowsMultipleSelection = true. (pass) — AppViewModel.swift:1178.
- [x] On .OK with one or more panel.urls, every selected file is added as a URL-backed PhotoAsset (no Data decode), collection is cleared then repopulated. (pass) — ImageCollection.addFromURLs(_:) calls clear() then constructs each PhotoAsset from the URL only (metadata + bookmark data), never reading file bytes into Data; mirrors addFromMediaVolume's URL-backed construction.
- [x] Editing navigates to .edit and loads (renders) the first selected image; the rest remain in the library for navigation. (pass) — openImages(urls:) loads collection.items.first(where: id == firstID) via openImage(url:assetID:), which calls navigation.move(to: .edit); remaining items stay in collection.items.
- [x] A bare single-selection keeps working exactly as today (no regression for the one-file case). (pass) — Covered by testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs; single-URL path produces one item and loads it as before.
- [x] Cancelled dialog (.cancel) leaves the collection and current edit untouched. (pass) — openImages(urls:) is only called inside the panel.runModal() == .OK branch, so a cancel never touches the collection or editor state.
- [x] Preserve ordering (sort by path) and duplicate/identity handling consistent with the rest of the importer. (pass) — addFromURLs sorts by standardizedFileURL.path with localizedStandardCompare (matches addFromMediaVolume) and dedups via Set<PhotoAssetID>, recording a scan warning for duplicates/unreadable files.
- [x] Swift 6 clean: no new Sendable/escape hatches. (pass) — Diff is synchronous MainActor UI code; no @unchecked Sendable, nonisolated(unsafe), or @preconcurrency introduced.
- [x] Unit tests cover multi-select, single-file, dedup, and cancellation; swift test stays green. (pass) — Tests/LumoKitTests/OpenImageDialogTests.swift covers sorted multi-open, single-file/dedup, and empty-selection (cancel-equivalent) leaving state untouched. Re-ran: swift test --filter OpenImageDialogTests (3 passed) and full swift test (748 passed, 34 expected skips, 0 failures).
Checks run:
- swift test --filter OpenImageDialogTests (3 passed, 0 failed)
- swift test (748 passed, 34 expected skips, 0 failures)
- git diff --check f4e5593~1 f4e5593 (clean)
Findings:
- Non-blocking (filed LUMO-180, verification label, parent LUMO-178): ImageCollection.addFromURLs(_:) duplicates most of addFromMediaVolume(_:files:)'s sort/read/dedup/append loop almost verbatim; worth factoring into a shared helper, but out of scope as a localized fix for this ticket.
Fixes:
- None
Verification commits:
- f4e5593
Actor: claude
Resolved model: sonnet
Pickup session: 01MTMZXINA894HG05U
Summary: Verified multi-select Open Image…: allowsMultipleSelection=true, ImageCollection.addFromURLs adds URL-backed PhotoAssets (clear-then-repopulate, sorted, deduped), first selection loads into .edit, cancel/single-file behavior preserved. swift test full suite green (748 passed). One non-blocking maintainability finding filed as LUMO-180 (duplication between addFromURLs and addFromMediaVolume).
