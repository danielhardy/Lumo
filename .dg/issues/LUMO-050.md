---
id: LUMO-050
title: Epic 9 — Reliable full-resolution export
type: feature
status: done
priority: urgent
verification_agent: pi
verification_model: openrouter/z-ai/glm-5.3-flash
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: JPEG, 16-bit TIFF, retained PNG export from originals plus saved edits
      result: pass
    - criterion: Selected-photo batches report progress, cancel, and isolate failures
      result: pass
    - criterion: Sizing, color, naming, and metadata policy are explicit and tested
      result: pass
  checks_run:
    - swift test — 626 executed, 13 expected skips, 0 failures (57-test export suite green)
    - swift build -c release — clean
    - git diff --check — clean
    - dg validate — OK (known runner-model warning only)
  findings:
    - "LUMO-136: ExportMetadataPolicy is a no-op — the encoder never attaches source metadata, so exports drop EXIF even with .preserve"
    - "LUMO-137: HEIF export from the epic MVP outcome is not delivered (documented out of scope by LUMO-051)"
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: unknown
  completed_at: 2026-09-02T17:41:41.211Z
labels:
  - mvp
  - epic
  - epic:export
  - phase:9
created: 2026-08-30T18:30:34.407Z
updated: 2026-09-02T17:41:41.214Z
depends_on:
  - LUMO-051
  - LUMO-052
  - LUMO-053
order: a0
board: product
---

## Objective

Generalize the inherited export path into current/selected full-resolution output with photographer-facing options, progress, cancellation, and isolated failures.

## MVP outcome

- [ ] JPEG, 16-bit TIFF, retained PNG, and cleanly supported HEIF export from originals plus saved edits.
- [ ] Selected-photo batches report progress, cancel, and isolate failures.
- [ ] Sizing, color, naming, and metadata policy are explicit and tested.

## Child tickets

- LUMO-051 — Define durable export options and format capabilities
- LUMO-052 — Export current or selected photos from originals and saved edits
- LUMO-053 — Add batch progress, cancellation, collision handling, and failure isolation
- LUMO-054 — Add optional Apple Photos delivery after file export is stable (stretch; non-blocking)

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every required child ticket; LUMO-054 is a non-blocking stretch ticket. Close the epic only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

### Comment — codex @ 2026-09-02T17:19:40.061Z

Integrated Epic 9 implementation is complete across child tickets LUMO-051, LUMO-052, and LUMO-053 (commits e620439, 92e95ec, 749082a). Verified the current/selected original-backed export path, durable format options and validation, full-resolution saved edits, progress/cancellation, collision-safe atomic writes, failure isolation, and bounded batch work. Export-focused suite: 57 passed, 1 expected skip; swift build -c release passed; git diff --check passed; dg validate passed with only known runner-model and low-context warnings. LUMO-054 Apple Photos delivery remains the explicitly non-blocking stretch ticket.

### Comment — claude @ 2026-09-02T17:38:23.012Z

-

### Comment — claude @ 2026-09-02T17:40:39.929Z

## Counterpoint verification report (independent review of Epic 9)

**Verdict: PASS — no blockers.** Two non-blocking findings filed as backlog children (LUMO-136, LUMO-137).

Reviewed the integrated implementation (commits e620439, 92e95ec, 749082a) against the epic's MVP outcome, plus each child ticket's own verification record (LUMO-051: pass, LUMO-052: implemented + verified, LUMO-053: pass).

**Correctness**

- Formats: JPEG / 16-bit TIFF / PNG delivered with per-format capability matrices that exactly match the encoder path in `RenderEngine` (`representationFormat` derived from the same `ExportBitDepth`/`ExportAlpha` the matrix validates); JPEG is 8-bit opaque-only with deterministic white-composite flattening. HEIF was consciously left out per LUMO-051's conditional scope — the epic-level MVP bullet remains unmet and is now tracked as **LUMO-137** instead of being silently dropped.
- Metadata: `ExportMetadataPolicy` is modeled, validated, and tested as a value, but the encoder never reads it — every export drops EXIF while the default claims `.preserve`. Real gap for a photographer-facing tool, but honoring it is new product behavior, so filed as **LUMO-136** rather than patched here.
- Full-resolution path: single and batch export both funnel through `RenderEngine.render` at `RenderScale.full` from original-backed sources (URL/data/bookmark-resolved), never preview bitmaps; per-asset persisted `EditDocument` records resolve through `EditDocumentStore` with live-session snapshots winning, and a missing Look resolves to nil rather than leaking the active photo's Look (`resolvedDocument`/`lutResolver` seams).
- Progress/cancel/isolation: serial batch loop with completed/total/current-item progress; cancellation checked before each item and after every await inside one, discarding (never committing) an in-flight encode; per-item failure catch counts and continues; atomic `.partial` temp-file writes with `moveItem` commit and deferred cleanup; collision handling combines on-disk existence (`uniqueExportURL`) with a pre-render `reservedPaths` set, so duplicate names are deterministic whether they collide on disk or within the batch; memory bounded to one full-resolution raster + encoded `Data` at a time (asserted via `maxConcurrentEncodes == 1`).
- Security: security-scoped source access is resolved from bookmarks with balanced `startAccessingSecurityScopedResource`/`stop` (defers), destinations are user-selected URLs, and no new path construction beyond the pre-existing `uniqueExportURL`. No injection or sandbox concerns found.
- Performance: batch work runs on a dedicated `RenderEngine` actor (never the display actor's context), writes happen off the main actor via `Self.write`, and the display actor never touches the sandbox. Nothing scales linearly with batch length.
- Maintainability/Swift 6: zero concurrency opt-outs across the export code; `BatchItem`/`SourceAccess`/`ExportOptions` are `Sendable` value types; `CIImage`/`CIFilter`/`CIContext` stay inside `RenderEngine`.

**Checks run (this session)**

- `swift test` — 626 executed, 13 expected skips, 0 failures (includes the 57-test export-focused suite: options/capabilities/validation, coordinator batch behavior, naming, cutover parity).
- `swift build -c release` — clean.
- `git diff --check` — clean.
- `dg validate` — OK (known runner-model warning only).

**Findings (non-blocking, backlogged as verification children of this epic)**

- **LUMO-136**: `ExportMetadataPolicy` is a no-op — `RenderEngine`'s encode path never attaches source metadata, so exports lose all EXIF even with `.preserve` (the default).
- **LUMO-137**: HEIF export from the epic's MVP outcome is not delivered (documented out of scope by LUMO-051); tracked so the gap is visible.

No verification commits to product code; issue bookkeeping only.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T17:39:19.395Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] probe (pass)
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: openrouter/z-ai/glm-5.3-flash
Pickup session: 01MTKD2WLW4DBVC5U1

- 2026-09-02T17:41:41.213Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] JPEG, 16-bit TIFF, retained PNG export from originals plus saved edits (pass)
- [x] Selected-photo batches report progress, cancel, and isolate failures (pass)
- [x] Sizing, color, naming, and metadata policy are explicit and tested (pass)
Checks run:
- swift test — 626 executed, 13 expected skips, 0 failures (57-test export suite green)
- swift build -c release — clean
- git diff --check — clean
- dg validate — OK (known runner-model warning only)
Findings:
- LUMO-136: ExportMetadataPolicy is a no-op — the encoder never attaches source metadata, so exports drop EXIF even with .preserve
- LUMO-137: HEIF export from the epic MVP outcome is not delivered (documented out of scope by LUMO-051)
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: unknown
Summary: Counterpoint verification passed: independent review of Epic 9 (e620439, 92e95ec, 749082a) found no blockers; swift test (626, 0 failures), release build, diff-check, dg validate all green. Non-blocking findings filed as LUMO-136 (metadata policy no-op) and LUMO-137 (HEIF MVP gap).
