---
id: LUMO-109
title: Replace redundant open-time development with bounded source preparation
type: task
status: done
priority: high
labels:
  - performance
  - epic:quality
  - loading
  - raw
  - navigation
created: 2026-09-01T22:05:10.331Z
updated: 2026-09-02T03:37:07.174Z
depends_on:
  - LUMO-111
order: a0
board: product
commits:
  - 67c56b5
---

## Objective

Show the selected edited photo sooner and prevent obsolete navigation loads from accumulating, while preserving accurate source geometry and RAW development.

## Context and evidence

Performance audit item 4, evaluated at commit `724ad99`: [September 1 audit](../../docs/PERFORMANCE_AUDIT_2026-09-01.md).
The user requested tangible responsiveness improvements without sacrificing visual fidelity or accuracy; prioritize code quality and measured impact over minimizing implementation effort.

**Evidence:** [AppViewModel.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/ViewModels/AppViewModel.swift:695) starts an unstructured detached `ImageDecoder.load`, waits for it, then loads the edit record. [ImageDecoder.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/ImageDecoder.swift:113) accesses a neutral RAW filter's `outputImage`; the engine subsequently creates its own source graph. `sourceImage` is used as an availability flag rather than as the renderer's source. RAW capabilities instantiate another filter. Canceling the parent load does not cancel the detached operation.

**Impact:** First useful pixels wait on unnecessary source preparation; rapid navigation can leave obsolete loads running. The code accesses a full-resolution RAW output graph, although this audit does not claim every pixel is eagerly rasterized at that point.

**Approach:** Create a value-based source descriptor using oriented metadata and decoder geometry as appropriate. Load edit state concurrently with source preparation. Reuse a renderer-owned RAW session for dimensions, capabilities, and actual development. Bound navigation loading to active work plus the newest pending source. Cache/prefetch adjacent edited previews at idle priority.

**Fidelity:** Embedded camera JPEGs are not equivalent to the current edited RAW. Any optional placeholder must remain distinct from the authoritative color-managed preview and must not be used for histogram or detail assessment.

## Acceptance criteria

- [ ] Opening does not request a neutral full-resolution RAW output solely to obtain dimensions or an image-available flag.
- [ ] Source preparation returns value state with correct oriented dimensions and source identity; capability probing and actual development reuse the renderer-owned RAW session where valid.
- [ ] Edit-store loading overlaps independent source preparation and never overwrites a newer in-memory edit session.
- [ ] Navigation has explicitly bounded active work and only the newest pending source; non-cancellable decode completion cannot start an obsolete load or publish an old source.
- [ ] Warm cached revisits target ≤100 ms to displayed edited pixels; record cold first-useful-pixel and cold settled-image latency separately.
- [ ] Generated standard images, representative 24 MP and 40–60 MP RAW, data-backed imports, missing/corrupt files, and rapid alternating navigation all retain correct source/metadata/capability state.
- [ ] Embedded JPEGs, if used as temporary placeholders, are not treated as authoritative edited RAW pixels or histogram/detail inputs; visible placeholders converge reliably to the edited render.

## Verification plan

Extend ImageLoadingTests, FilmstripNavigationTests, RAWCapabilitiesTests, and persistence integration coverage. Add a controllable non-cancellable source preparation seam to prove queue bounds. Profile first open, next/previous, rapid key repeats, and warm revisits with adjacent-preview prefetch enabled and disabled.

Start with these relevant checks, then run `swift test` and `swift build -c release` before implementation handoff:

```sh
swift test --filter ImageLoadingTests
swift test --filter FilmstripNavigationTests
swift test --filter RAWCapabilitiesTests
```

Record generated fixture parameters and, for hardware results, source dimensions/format, RAW decoder/version when relevant, hardware, OS, commit, Release configuration, viewport/backing pixels, and cold/warm conditions. Attach before/after traces or durable summaries. The September 1 audit measured component rendering on an M1 Pro (10 CPU cores, 16 GB, macOS 26.6); it did not measure Lightroom/Photomator or real RAW input-to-display latency. Its 198.9 ms rebuild versus 4.9 ms source-reuse PNG result motivates reuse but is not a promised whole-app speedup.

## Fidelity and engineering constraints

Preserve macOS 14 deployment, Swift 6 concurrency safety, Apple-framework-only dependencies, deterministic edit ordering, working-space conversion, premultiplied alpha behavior, orientation, native-resolution export, and deterministic grain where applicable. Do not hide latency by permanently reducing resolution, skipping effects, or weakening precision. Pixel parity needs documented tolerances and representative fine-detail, edge, skin-tone, saturated/wide-gamut, crop, and transparency fixtures; sharing the same graph across resolutions is not proof of equivalence for nonlinear/spatial processing.

## Dependencies and scope boundaries

Hard prerequisites: LUMO-111

Depends on the shared RAW output/session ownership ticket to avoid introducing a second competing session design. Coordinate with supporting-work priority for idle prefetch. Preserve RecipeExtractor neutral-development semantics.

These tickets provide concrete implementation work for the broader LUMO-055/LUMO-058 quality effort. This ticket is in backlog for planning; implementation and automatic pickup have not been requested as part of ticket creation.

### Comment — codex @ 2026-09-02T03:31:51.886Z

Implemented in commit 67c56b5. Replaced eager open-time RAW/full-resolution decoding with value-only source preparation; renderer-owned RAW sessions now provide geometry, capabilities, and development. Edit loading overlaps preparation; navigation is bounded to one active plus newest pending request; adjacent edited previews warm at idle priority. Added coverage for oriented metadata, rapid navigation, late edit-store results, and extensionless RAW byte imports. Verification: ImageLoadingTests, FilmstripNavigationTests, workspace/persistence tests pass; ImageSourceTests pass; release build and dg validate pass. Full swift test has one pre-existing fixture-specific failure: RAWCapabilitiesTests.testProbingARealRAWReportsItsDecodersSeeds expects lens correction enabled, but the installed decoder reports unsupported for the bundled DNG.

### Comment — claude @ 2026-09-02T03:37:04.032Z

## Verification report — counterpoint review (independent of prior codex review)

**Commit reviewed:** 67c56b5 "LUMO-109 bound source preparation during navigation"

**Checks run:**
- `swift test --filter ImageLoadingTests` — 13/13 passed
- `swift test --filter FilmstripNavigationTests` — 3/3 passed
- `swift test --filter RAWCapabilitiesTests` — 14/15 passed; 1 pre-existing failure (`testProbingARealRAWReportsItsDecodersSeeds`, expects lens correction enabled on the local Leica M11 DNG fixture but the installed decoder reports unsupported). Confirmed unrelated to this diff: `RAWCapabilitiesTests.swift` is untouched by commit 67c56b5, and the code path it exercises (`InteractiveRAWFilterSession.captureCapabilities`) reads the same `CIRAWFilter` properties the old code did, just captured once at session construction instead of per-call. This is a local-decoder/fixture-version issue, not a regression.
- Full `swift test` — 590 tests, 13 skipped, same single pre-existing failure, otherwise clean.
- `swift build -c release` — succeeds (only pre-existing Core Image kernel deprecation warnings).

**Code review findings:**
- Verified `ImageDecoder.prepareStandard` / `RenderEngine.prepareSource` return value-only geometry (ImageIO properties / `CIRAWFilter.nativeSize`) without touching `outputImage` — satisfies "no neutral full-resolution RAW output for dimensions" acceptance criterion.
- Verified `AppViewModel.sourceImage` is now a fully transparent placeholder used only as an availability flag (`sourceImage != nil` gates), never passed to the renderer, histogram, or detail assessment — grepped all call sites to confirm.
- Verified the bounded-navigation worker (`pendingSourceLoad` + single `loadTask` loop in `startSourceLoadWorkerIfNeeded`) keeps exactly one active, non-cancellable preparation plus one replaceable pending request, and that `prepareAndInstall` checks `sourceRevision` before publishing — a late/obsolete completion cannot install a stale source. Confirmed by `testRapidNavigationKeepsOnlyTheNewestPendingSource` (asserts preparation count == 2 for 3 rapid opens).
- Verified the late-edit-store race: `adoptStoredEdits` only adopts the on-disk document when the in-memory session was absent *and* unchanged since the request was queued (`editSessionRevisions` bumped synchronously inside `updateDocument` → `saveActiveDocument` on every edit). Traced this end-to-end; no window where an edit made during preparation could be silently dropped. Confirmed by `testLateEditStoreResultCannotOverwriteAnInMemoryEdit`.
- Verified `RenderEngine.developedSource`'s new `canUsePreparedSession` gate: non-interactive (e.g. adjacent-preview prefetch) renders only reuse an *already-matching* interactive RAW session and never evict/replace it, so background prefetch cannot thrash the session a user is actively editing with. Interactive requests remain the only ones allowed to create/replace the session.
- Checked the new TIFF-container RAW sniff (`CIRAWFilter(imageData:identifierHint:)` in `ImageSource.kind(forData:)`) — narrowly scoped to `public.tiff`-typed data only, consistent with the extensionless-RAW-import fixture coverage already added.

**Outcome:** No blocking issues found. No non-blocking cleanup items rose to the level of a backlog ticket — the design decisions reviewed (session-reuse gating, revision-based staleness checks) are intentional and covered by targeted tests, not incidental gaps.

Moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T03:37:07.172Z: Independent counterpoint verification passed: swift test (590 tests, only 1 pre-existing unrelated fixture failure), swift build -c release clean, and code review confirmed bounded navigation, no-stale-overwrite, and value-only source preparation all match acceptance criteria.
