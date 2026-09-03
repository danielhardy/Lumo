---
id: LUMO-119
title: Schedule representative human-operator hardware capture for LUMO-118
type: task
status: done
priority: urgent
labels:
  - verification
created: 2026-09-02T00:38:00.379Z
updated: 2026-09-02T02:25:26.128Z
order: yh
board: product
---

## Objective

Provide a fallback for a representative hardware capture if the automated LUMO-118 command cannot
run. This is no longer the primary path: the normal capture is automated through `xctrace` and does
not require a human-operated Instruments session or UI click-through.

## Context

Independent counterpoint verification of LUMO-118 (2026-09-02, HEAD 90c1b95) found zero archived
hardware rows, but two released Sony ILCE-7M2 ARW fixtures are now available in `realworldtest/`.
The remaining work is normally handled by `scripts/run-lumo-118-capture.sh` using one of those
source files and display access; exhaustive matrix coverage is not required. Manual capture is only
a fallback when the automated command cannot access the display or tracing service.

The capture command drives the benchmark and tracing service; it does not attempt to automate the
full app UI, which is outside this ticket's scope.

## What's needed

- A logged-in Mac with a real display and a Release build (`swift build -c release`).
- `xctrace` with Points of Interest + Metal System Trace available.
- One or more representative released source files, including the ARW fixtures in `realworldtest/`.
- Run `scripts/run-lumo-118-capture.sh` with one source, then use its generated trace and summary.
  Cold/warm and supporting-work comparisons may be added later; driving every control and every
  matrix row is explicitly out of scope.
- Update docs/PERFORMANCE_CAPTURE_MATRIX_2026-09-01.md's "Current checkout record" section with the captured subset and an explicit list of unrun combinations.

## Scope boundaries

Do not attempt to satisfy this with generated/synthetic data or the fake-renderer coordinator
benchmark. This ticket is closed by the automated command (or a human fallback) recording a representative capture, with unavailable
matrix combinations documented explicitly rather than implied to be measured.

Parent: LUMO-118 (manual fallback only; this ticket is no longer a dependency).

Closure: The automated LUMO-118 capture completed successfully, so this manual fallback is obsolete
and no longer required.

## Agent log

- 2026-09-02T02:25:26.126Z: Obsolete: the automated LUMO-118 capture completed successfully, so no manual hardware-capture session is required.
