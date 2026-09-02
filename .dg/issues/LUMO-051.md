---
id: LUMO-051
title: Define durable export options and format capabilities
type: task
status: done
priority: urgent
verification_agent: pi
verification_model: openrouter/z-ai/glm-5.3-flash
labels:
  - mvp
  - epic:export
  - phase:9
created: 2026-08-30T18:30:34.634Z
updated: 2026-09-02T16:46:56.258Z
depends_on:
  - LUMO-012
  - LUMO-008
estimate: 5
order: a0
board: product
---

## Objective

Model output format, quality, full size/long edge, color space, filename policy, destination, and metadata behavior without UI dependencies.

## Context

Part of **Epic 9 — Reliable full-resolution export**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Retain JPEG, 16-bit TIFF, and PNG; enable HEIF only where encoding is clean and testable.
- Define resize semantics with no accidental upscaling by default.
- Enumerate supported color spaces and bit-depth/alpha constraints per format.
- Validate combinations before an export begins.

## Acceptance criteria

- [ ] Invalid format/bit-depth/color/alpha combinations fail with actionable errors.
- [ ] Long-edge resizing preserves aspect ratio and orientation.
- [ ] Defaults produce full-size high-quality output.
- [ ] Options are Sendable and testable independently of panels.

## Verification

- Add capability matrix, validation, sizing, and default tests.

## Out of scope

- Print layouts.
- Arbitrary ICC profile editing unless supported cleanly.

### Comment — codex @ 2026-09-02T15:35:19.047Z

Implemented in commit e620439. Added Codable/Sendable ExportOptions covering format, quality, full-size/long-edge sizing, color space, bit depth, alpha, filename, destination, and metadata policy; added per-format capability matrices and actionable preflight validation; wired options through coordinator/render requests and encoder sizing/precision/color/alpha behavior; retained JPEG, 16-bit TIFF, and PNG while leaving HEIF out until cleanly testable. Added panel-free capability, validation, sizing/orientation, defaults, Codable, filename, and renderer tests. Verification: swift test (622 passed, 13 expected skips), swift build -c release, git diff --check, and dg validate OK (pre-existing pickup-model and LUMO-050 context warnings only).

### Comment — pi @ 2026-09-02T16:46:02.535Z

## Counterpoint verification report (independent review)

**Verdict: PASS — no blockers.** Two non-blocking findings filed as backlog children (LUMO-134, LUMO-135).

Reviewed commit e620439 against the objective and acceptance criteria.

**Correctness**

- Capability matrix matches the encoder path: TIFF/PNG accept 8/16-bit + alpha, JPEG is 8-bit opaque-only; `RenderEngine` derives `representationFormat` from the same `ExportBitDepth`/`ExportAlpha` values the matrix validates, so a validated combination is always encodable. HEIF correctly left out per scope.
- Preflight validation runs before any render work in all three entry points (`RenderEngining.encode`, `ExportCoordinator.performExport`, `performBatchExport`), with per-case, actionable `LocalizedError` messages; the quality guard rejects NaN/inf as well as out-of-range values.
- Long-edge sizing: `outputSize(for:)` preserves aspect ratio and orientation, never upscales (factor clamped to 1), and guards non-finite/degenerate extents. The engine maps sizing to a square `RenderScale.preview` box, which fits-without-upscaling by construction and was verified end-to-end by the 100x50 -> 40x20 render test.
- Defaults: `ExportOptions.default` is full-size, quality 0.95, sRGB (`.current`), 8-bit/opaque for JPEG — full-size high-quality as required, and test-asserted.
- Export options are value-only (`Codable`/`Sendable`, no UI or render objects); `RenderRequest` gained `exportOptions` without breaking the legacy initializer spelling. No concurrency opt-outs introduced.
- Alpha flattening composites over white inside the actor-local CI graph; JPEG opaque output is deterministic rather than encoder-dependent.
- No security concerns: destinations are user-selected URLs via the existing `Self.write` path; no new file I/O or path construction beyond the pre-existing `uniqueExportURL`.

**Findings (non-blocking, backlogged)**

- **LUMO-134**: plan/execution size drift — `ExportSizing.outputSize(for:)` rounds to nearest while the engine's `extent.integral` rounds outward; a 3333x5000 source at longEdge 2000 plans 1333x2000 but encodes 1334x2000 (reproduced in this session). Aspect ratio/orientation still correct, so acceptance criteria hold; filed for reconciliation before the Step 12 export UI reports planned sizes.
- **LUMO-135**: dead speculative aliases in the new `ExportOptions.swift` (`ExportAlphaMode`, `ExportResize`, `size`, `metadataPolicy`, `bit8`/`.bit16`, `ExportAlpha.none` — zero callers) and a misleading `outputFormatMismatch` message on the unreachable misuse path where `exportOptions` is paired with `.raster` output.

**Checks run (this session)**

- `swift test` — all suites pass, 609 executed test cases, 0 failures (includes the new capability-matrix, validation, sizing/orientation, defaults, Codable, filename, and renderer tests).
- `swift build -c release` — clean.
- `git diff --check` — clean.
- `dg validate` — OK (pre-existing pickup runner-model and LUMO-050 low-context warnings only).
- Ad-hoc fractional-scale probe (added, run, removed — tree left clean) confirming the LUMO-134 drift.

No verification commits to product code; issue bookkeeping only.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T16:46:56.256Z: Counterpoint verification passed: independent review of e620439 found no blockers; all acceptance criteria hold (capability matrix, preflight validation, sizing, defaults, Sendable/Codable options). Checks: swift test (609 cases, 0 failures), swift build -c release, git diff --check, dg validate OK. Non-blocking findings filed as LUMO-134 and LUMO-135.
