---
id: LUMO-137
title: Add HEIF export format when cleanly testable (Epic 9 MVP gap)
type: task
status: done
priority: low
labels:
  - verification
created: 2026-09-02T17:36:12.415Z
updated: 2026-09-02T20:02:06.620Z
depends_on:
  - LUMO-050
order: a0
board: product
commits:
  - c6b971a
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: .heif appears in ExportFormat.allCases with correct UTType/extension and capability matrix
      result: pass
    - criterion: Encoder round-trip test verifies a HEIF export decodes with the expected dimensions/color space
      result: pass
    - criterion: Unsupported-environment failures surface as a per-item export failure (batch isolation), never a crash or partial file
      result: pass
    - criterion: swift test green; no public API outside LumoKit's existing surface changes
      result: pass
  checks_run:
    - swift test — 642 executed, 14 expected skips, 0 failures
    - swift test --filter HEIFRoundTrip — real encode/decode passed on this machine (HEVC encoder available), exercising the round trip rather than the XCTSkip fallback
    - swift build -c release — clean
    - git diff --check c6b971a~1 c6b971a — clean
    - git status --porcelain -- Sources Tests Package.swift — clean (no stray edits from review)
  findings:
    - "Non-blocking: RenderEngine.swift's encode() doc comment still says metadata is written \"for all three export formats\" — now four with HEIF. Cosmetic only, left as-is per localized-fix scope."
  fixes: []
  verification_commits:
    - c6b971a
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-02T20:02:06.618Z
  session: 01MTKIRAW1QV723ERY
---

## Objective

Deliver the one Epic 9 MVP bullet that shipped unmet: HEIF export, added only where encoding is clean and testable.

## Context

Found during LUMO-050 (Epic 9) counterpoint verification — non-blocking follow-up.

The epic's MVP outcome lists "JPEG, 16-bit TIFF, retained PNG, and cleanly supported HEIF export". LUMO-051's scope was conditional ("enable HEIF only where encoding is clean and testable") and HEIF was consciously left out with the rationale recorded in its verification report — a defensible reading of the child ticket, but the epic-level MVP bullet remains unmet and should be tracked rather than silently dropped.

Constraints to respect when picking this up:

- `ExportFormat` is a load-bearing contract: `CaseIterable`/`Identifiable`, exact raw values, drives `NSSavePanel` seeding and capability matrices (see the doc comment in `ExportFormat.swift`). Adding `.heif` must update `capabilities`, `defaultBitDepth`/`defaultAlpha`, and the `ExportFormatAccessoryView` accessibility strings.
- macOS 14 minimum: HEIF encoding via `CGImageDestination`/CIContext `.heif`/`.heic` UTTypes must be verified against the deployment target, and behavior on unsupported hardware (no HEVC encoder) must fail gracefully rather than corrupt output.
- Follow the precedent of LUMO-051's "cleanly testable" bar: capability matrix, validation, and an encoder round-trip test before shipping.

## Acceptance criteria

- [ ] `.heif` appears in `ExportFormat.allCases` with correct UTType/extension and capability matrix.
- [ ] Encoder round-trip test verifies a HEIF export decodes with the expected dimensions/color space.
- [ ] Unsupported-environment failures surface as a per-item export failure (batch isolation), never a crash or partial file.
- [ ] `swift test` green; no public API outside `LumoKit`'s existing surface changes.

## Out of scope

- AVIF or any non-Apple encoder.

### Comment — codex @ 2026-09-02T19:58:40.571Z

Implemented in commit c6b971a. Added HEIF to ExportFormat with stable HEIF/HEIC UTI and .heic naming, 8-bit opaque capability defaults, Image I/O encoding with quality/metadata support, and updated export picker accessibility text. Added format/capability contract coverage, a real HEIF encode/decode round-trip test for dimensions and Display P3, and batch isolation coverage proving encoder failures leave no output or partial file. Verification: swift test — 642 passed, 14 expected skips; swift build -c release — passed; git diff --check — passed; dg validate — OK with pre-existing pickup-runner model and LUMO-138 context warnings.

### Comment — claude @ 2026-09-02T20:02:06.393Z

Counterpoint verification (independent review, post-human-review): PASS. Reviewed commit c6b971a against acceptance criteria — .heif case added to ExportFormat with correct UTType (.heic), extension, capability matrix (8-bit, opaque, sRGB/Display P3), and defaultAlpha; RenderEngine encode() routes HEIF through the same CGImageDestination path as JPEG/TIFF/PNG with lossy-quality applied and failures surfacing as ImageError.exportFailed (no crash, no partial file — confirmed by re-running the new batch-isolation test); the round-trip test decodes a real HEIF export and checks dimensions/color space, with an XCTSkip fallback if no HEVC encoder is present. Re-ran: swift test (642 executed, 14 expected skips, 0 failures), swift test --filter HEIFRoundTrip (passed for real on this machine, not the skip path), swift build -c release (clean), git diff --check (clean), git status --porcelain (clean, no side-effect edits). One cosmetic non-blocker: the encode() doc comment still says 'all three export formats,' now four — left as-is, not worth a ticket. No blockers found; moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T20:02:06.619Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] .heif appears in ExportFormat.allCases with correct UTType/extension and capability matrix (pass)
- [x] Encoder round-trip test verifies a HEIF export decodes with the expected dimensions/color space (pass)
- [x] Unsupported-environment failures surface as a per-item export failure (batch isolation), never a crash or partial file (pass)
- [x] swift test green; no public API outside LumoKit's existing surface changes (pass)
Checks run:
- swift test — 642 executed, 14 expected skips, 0 failures
- swift test --filter HEIFRoundTrip — real encode/decode passed on this machine (HEVC encoder available), exercising the round trip rather than the XCTSkip fallback
- swift build -c release — clean
- git diff --check c6b971a~1 c6b971a — clean
- git status --porcelain -- Sources Tests Package.swift — clean (no stray edits from review)
Findings:
- Non-blocking: RenderEngine.swift's encode() doc comment still says metadata is written "for all three export formats" — now four with HEIF. Cosmetic only, left as-is per localized-fix scope.
Fixes:
- None
Verification commits:
- c6b971a
Actor: claude
Resolved model: sonnet
Pickup session: 01MTKIRAW1QV723ERY
