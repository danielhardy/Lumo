---
id: LUMO-077
title: "LUMO-075 follow-up: main-preview NSImage fallback path is dead in production — remove or re-scope"
type: task
status: done
priority: low
labels:
  - verification
created: 2026-09-01T02:06:52.179Z
updated: 2026-09-01T05:08:04.353Z
order: a0
board: product
commits:
  - 59013b0
---

## Objective

LUMO-075 follow-up: main-preview NSImage fallback path is dead in production — remove or re-scope

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-01T05:06:36.421Z

Implemented in commit 59013b0. Removed the production previewNSImage/originalPreviewNSImage state and PreviewView fallback branches; both preview panels now render from PreviewSurface. Re-scoped the raster-only compatibility path to convert CGImage into CIImage for the same surface, preserving non-GPU/test conformers. Updated coverage to wait on the surface. Verification: swift test (455 passed, 24 expected skips), swift build -c release, git diff --check, dg validate (only pre-existing runner-model/context warnings).

### Comment — claude @ 2026-09-01T05:08:00.571Z

## Verification report — LUMO-077 (independent counterpoint review)

**Scope:** commit 59013b0 (removes previewNSImage/originalPreviewNSImage from AppViewModel, removes the NSImage fallback branches from PreviewView, re-points ExportCutoverTests at previewSurface).

**Correctness**
- Confirmed `previewNSImage`/`originalPreviewNSImage` have no remaining references anywhere in Sources or Tests.
- Traced the consolidated `publishPreview` control flow against the pre-change version line by line: the old code ran the settled-phase baseline-queue/histogram-update block whenever either `gpuImage` or `image` was present (in two separate branches keyed off a `guard let cgImage`). The new code reaches the same block via a single `guard publication.gpuImage != nil || publication.image != nil else { ... }`, so the settled-phase side effects (comparison baseline scheduling, histogram update, status message on total failure) fire under exactly the same conditions as before. No behavior change.
- Confirmed via PreviewCoordinator.swift:218-222 that `image` (CGImage) is only populated when `gpuImage` is nil — i.e. the retained raster path in `publishPreview` is genuinely a compatibility seam for non-GPU `RenderEngine` conformers (used by `FakeRenderEngine` in tests) and never competes with the production GPU path, matching the inline comment.
- `originalPreviewSurface.present(CIImage(cgImage:), ...)` correctly replaces the removed `originalPreviewNSImage` assignment with no loss of the actor/task cancellation guards above it.

**Checks run (independently, not just re-trusting the author's log)**
- `swift build` — clean.
- `swift test` — 455 passed, 24 skipped, 0 failures (matches claimed count).
- `swift build -c release` — clean.
- `git diff --check 59013b0^ 59013b0` — no whitespace errors.

**Maintainability / security / performance**
- No new abstractions, no public API/schema changes, no migrations.
- `docs/CODE_REVIEW.md:59` still mentions `previewNSImage` by name, but that's a historical note describing a fixed-and-superseded issue (B-series), not a live reference — left as-is since it documents what was true when B was fixed.
- No security-relevant surface touched (no I/O, no new external input handling).
- No performance regression: this removes an NSImage allocation/copy on every settled publish, which is a small win, not a cost.

**Verdict:** PASS. No blockers found. No new backlog tickets warranted — this is a clean, correctly-scoped removal.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T05:08:04.351Z: Independent verification passed: removal of previewNSImage/originalPreviewNSImage confirmed behavior-preserving (settled-phase side effects fire under identical conditions), non-GPU raster compatibility seam verified never to compete with production GPU path, all refs removed, swift test/build/release all clean, git diff --check clean. No blockers, no follow-up tickets needed.
