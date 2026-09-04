---
id: LUMO-179
title: Imported photos should be durable / remain in the library
type: feature
status: done
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - persistence
created: 2026-09-04T13:26:53.529Z
updated: 2026-09-04T14:17:45.452Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T14:17:45.445Z
  session: 01MTN0403N3BA7XDZ4
---

**Type:** Feature
**Component:** `LumoKit/Models/ImageCollection.swift` + `LumoKit/ViewModels/AppViewModel.swift`
**Relates to:** LUMO-178 (multi-open dialog) — this is about what happens *after* the photos are in.

## 1. Problem

Importing a photo lets you manipulate and edit it, but importing the next one wipes the previous
ones. Two distinct failures combine here:

1. **In-session, each new import discards the rest.** `AppViewModel.openImageDialog()` (and other
   single-import paths) calls `collection.clear()` before opening the new file. `clear()` sets
   `items = []` and tears down selection/thumbnails/projection, so every previously imported photo
   is gone from the library. The user can edit the current one, but anything they imported earlier
   is unreachable and effectively deleted from the session.

2. **Cross-session, imported photos are not saved.** Photos picked via the Photos picker or opened
   one-off ("one-off single-image opens") land in the collection **without** a `sourceFolderURL` —
   see the comment on `ImageCollection.sourceFolderURL`. Only source-folder assets (and their
   edit/culling state) are persisted via bookmark + culling-state on disk. In-memory imports
   survive only for the running session and are lost on relaunch, unlike a source-folder photo.

The user's expectation is the opposite of both: *import once, keep it.* Editing one photo should
not erase another, and an imported photo should not disappear when the app is restarted.

## 2. Requirement (acceptance criteria)

1. **In-session retention.** Importing a further photo does **not** remove already-imported
   photos. The collection keeps every previously imported (and source-folder) item; only the
   *currently edited* photo changes. Previously imported photos remain navigable in the library.
2. **Cross-session persistence.** Newly imported (non-source-folder) photos are written to a
   Lumo-managed **library folder on disk** and adopted as collection items through that folder, so
   they survive app relaunch — alongside existing source-folder assets and their edit state.
3. **Edit durability.** Edits applied to an imported photo persist with it (already true for
   source-folder assets via `persistCullingState`/library state; the library-folder path must
   carry the same edit persistence, not just the input).
4. Existing behaviour for source-folder libraries is unchanged; this only adds durability to the
   previously in-memory-only import paths.

## 3. Design / implementation guidance

- **Stop clearing on open.** `openImageDialog()` (LUMO-178 path) and other single-import helpers
  currently call `collection.clear()`. For durability they should instead **adopt** the new file
  into the collection (append to `items`) and only switch the *current edit* via `load(...)`.
  Migration of an existing source-folder library into a "library folder on disk" is *not*
  required — only future imports need to be durable.
- **Add a Lumo library folder.** Choose/create one managed directory (sandboxed, e.g. under
  `Application Support/Lumo/Library/`). On import of a non-source-folder photo, copy the file into
  this folder (copy, not move — never disturb the user's source), then create a `PhotoAsset`
  pointing at the copied URL with bookmark data, add it to the collection, and persist. Reuse the
  existing bookmark/persistence machinery rather than inventing new on-disk identity rules.
- **Mirror the source-folder asset model.** A source-folder item keeps stable `id`, edit session,
  culling state and bookmark. The library-folder path should give imported photos the same stable
  identity and edit persistence so they behave like normal library members, not throwaway imports.
- **Idempotency / re-import.** Re-importing a file that already exists in the library folder should
  not create duplicate copies or duplicate items — dedupe by resolved path (cf. `PhotoAsset`
  canonical-path / duplicate handling already used in the importer).
- **Swift 6 clean.** No new shared mutable state; keep edits to item construction/inside the
  collection.

## 4. Where to look

- `Sources/LumoKit/Models/ImageCollection.swift`
  - `clear()` (L996) — the wipe to stop calling on import; understand what it resets.
  - `sourceFolderURL` (L142) + folder adoption flow (`setSourceFolder…`, `scanFromSourceFolder`)
    — the durability pattern to mirror.
  - `persistCullingState(for:)`, `restoredCullingState(for:)` (L1234+) — edit-state persistence to
    carry over.
- `Sources/LumoKit/ViewModels/AppViewModel.swift` — import/open helpers that call `collection.clear()`.
- `Sources/LumoKit/Models/LumoSettings.swift` — folder-kind bookmark persistence pattern.
- `Sources/LumoKit/Models/PhotoAsset.swift` — stable identity / canonical-path / duplicate rules.

## 5. Testing

- In-session: after importing A then B, `collection.items` contains both; selecting/edting B does
  not remove A and vice versa. Existing single-import test still passes (one item, editor shows it).
- Persistence: a photo imported in one session is present in the collection after restart; its edit
  state round-trips. Exercise import → quit → relaunch with the folder bookmark intact.
- Re-import of an already-librared photo yields a single item (no duplicates), and the source file
  is left untouched.
- `swift test` stays green; no new escape hatches (`@unchecked Sendable`, etc.).

---
Ported from a spec drafted by another AI session as `docs/LUMO-178-imported-photos-durable.md`,
which was never registered as a real dg ticket (no `dg issue create` was run). Re-filed here as
LUMO-179 since the intended LUMO-177/178 numbers were already taken/reused.

## Agent log

- 2026-09-04T14:17:45.449Z: Verification report
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
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTN0403N3BA7XDZ4
Summary: Added durable managed-library imports for one-off URLs, Photos data, and removable media; imports now append, deduplicate, preserve source files, restore on relaunch, and keep edit/culling state stable. Updated regression coverage and test isolation.
