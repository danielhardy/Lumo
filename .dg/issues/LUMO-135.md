---
id: LUMO-135
title: "ExportOptions: remove dead speculative aliases and clarify non-encoded-output mismatch error"
type: task
status: done
priority: low
labels:
  - verification
created: 2026-09-02T16:43:12.601Z
updated: 2026-09-02T19:52:33.202Z
depends_on:
  - LUMO-051
order: a0
board: product
commits:
  - 801b152
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 801b152
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-02T19:52:33.201Z
  session: 01MTKIFSTFITQZ5ZDO
---

## Objective

Remove unused compatibility aliases from the new export-options model and make the preflight format check produce an accurate error when it is (mis)used with a non-encoded render output.

## Context

Found during LUMO-051 counterpoint verification (non-blocking; commit e620439).

`Sources/LumoKit/Models/ExportOptions.swift` ships several aliases with zero callers anywhere in the package or tests (verified by grep at verification time):

- `typealias ExportAlphaMode = ExportAlpha` and `typealias ExportResize = ExportSizing`
- `ExportOptions.size` and `ExportOptions.metadataPolicy` accessors
- `ExportBitDepth.bit8` / `.bit16` and `ExportAlpha.none` static aliases (`none` is especially confusable with `Optional.none`)

If the Step 12 export UI ends up needing different spellings, add them then, with callers — speculative surface area in a fresh type invites phantom expectations.

Separately, the preflight guard in `RenderEngine.render` (`guard case .encoded(let format, _) = request.output, format == options.format`) throws `ExportOptionsError.outputFormatMismatch(expected:actual:)` even when the output is `.raster`, reporting `actual` as the options' own format — e.g. "request JPEG, but the render requested JPEG". Unreachable through product call paths today (the engine's `encode` and the coordinator always pair `exportOptions` with `.encoded`), but the message would mislead the next person who hits it while wiring a new caller.

## Acceptance criteria

- [ ] No alias/accessor in `ExportOptions.swift` without at least one caller (or it is deliberately reintroduced with one in the same change).
- [ ] A `RenderRequest` with `exportOptions` but non-encoded output produces an error message that names the actual situation (or such combinations are rejected with a dedicated case).
- [ ] `swift test` green; no public API outside `LumoKit`'s existing surface changes.

## Implementation notes

All aliases are internal to `LumoKit`, so removal is a non-breaking cleanup. The error case could either gain a new `ExportOptionsError` variant or the guard could simply skip the format equality check when output is not `.encoded` (options validation still runs).

### Comment — codex @ 2026-09-02T19:49:46.995Z

Implemented in 801b152. Removed the unused ExportOptions aliases/accessors (ExportAlphaMode, ExportResize, size, metadataPolicy, bit8, bit16, and ExportAlpha.none). Added ExportOptionsError.outputRequiresEncoded so export options paired with raster output report the actual output kind, while encoded format mismatches retain their existing error. Added regression coverage for the raster case. Verification: swift test (640 passed, 14 expected skips), swift build -c release, git diff --check, and dg validate passed; validator retained only pre-existing warnings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T19:52:33.202Z: Verification report
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
- 801b152
Actor: claude
Resolved model: sonnet
Pickup session: 01MTKIFSTFITQZ5ZDO
Summary: Counterpoint verification passed: aliases removed cleanly (no dangling references), outputRequiresEncoded error added and correctly distinguishes raster-vs-encoded mismatch from format mismatch, regression test covers the raster case.
