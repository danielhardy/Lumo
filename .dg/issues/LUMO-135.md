---
id: LUMO-135
title: "ExportOptions: remove dead speculative aliases and clarify non-encoded-output mismatch error"
type: task
status: backlog
priority: low
labels:
  - verification
created: 2026-09-02T16:43:12.601Z
updated: 2026-09-02T16:44:09.988Z
depends_on:
  - LUMO-051
order: zzz
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
