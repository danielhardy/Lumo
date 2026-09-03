---
id: LUMO-118
title: Archive representative hardware capture data for LUMO-114
type: task
status: done
priority: urgent
labels:
  - verification
created: 2026-09-02T00:01:41.196Z
updated: 2026-09-02T02:26:27.203Z
order: n
board: product
---

## Objective

Archive a representative, reproducible subset of Release-build hardware captures for the available
standard/RAW sources. This provides grounded data for the performance work without requiring an
exhaustive benchmark of every source size, control, cache state, or supporting-work combination.

## Context

LUMO-117 built the automated infrastructure this ticket needs (MetalPresentationBenchmark.swift, TracingOverheadBenchmark.swift, docs/PERFORMANCE_CAPTURE_MATRIX_2026-09-01.md). A representative ARW capture is now archived in docs/LUMO-118-DSC07826-20260901-201604-summary.md; the full matrix remains intentionally out of scope. The reduced capture uses a logged-in Mac with a display, available source files, and the repository's xctrace wrapper. The wrapper drives the benchmark and tracing service without manual Instruments or UI interaction.

Verified during LUMO-114 counterpoint re-verification (2026-09-02): both opt-in benchmarks run successfully and produce real numbers on this machine (`LUMO_METAL_BENCHMARK=1 swift test --filter MetalPresentationBenchmark` and `LUMO_TRACE_BENCHMARK=1 swift test --filter TracingOverheadBenchmark`), confirming AC6/AC8 infrastructure is genuine, not just present. The representative capture requirement is satisfied using the available ARW source; the full matrix remains optional future profiling.

## Acceptance criteria

- [x] Archive at least one representative automated Release capture using an available source
  file (standard or RAW), recording Mac/chip/memory, OS, commit, Release configuration, source
  dimensions/format, viewport/backing pixels, requested/effective render dimensions, and an
  attached xctrace trace or durable summary. Use `scripts/run-lumo-118-capture.sh` so no manual
  UI interaction is required.
- [x] For any available RAW source, record the RAW decoder/version in the capture summary. Cold/warm
  and supporting-work comparisons are optional follow-up measurements, not completion gates for
  this representative capture. A specific 24 MP or 40–60 MP file is welcome but not required when
  that source is unavailable.
- [x] Update docs/PERFORMANCE_CAPTURE_MATRIX_2026-09-01.md's "Current checkout record" section to
  list the representative archived captures and explicitly identify unrun matrix combinations;
  this ticket does not claim exhaustive coverage of every row or control.

## Dependencies and scope boundaries

Requires a logged-in macOS session with a real display and one or more available representative
source files. The capture itself is automated through `xctrace`; no manual Instruments session or
UI interaction is required. Parent: LUMO-114, which no longer blocks on completion of this capture
follow-up. LUMO-119 was a manual-capture fallback and is now closed as obsolete.

The full capture matrix remains a planning aid for future profiling. Missing source sizes,
controls, or matrix combinations should be recorded as unavailable rather than fabricated or
treated as a blocker.


### Comment — codex @ 2026-09-02T00:36:54.798Z

Investigation complete: no code change can satisfy this capture-only issue from the current checkout. The matrix still has no archived STD traces or measured rows, and the repository contains no licensed 24 MP or 40–60 MP RAW fixtures. Although this host currently reports an M1 Pro and active displays, completing AC7 still requires a human operator to run the Release app while manually recording Points of Interest + Metal System Trace and driving every matrix control with representative RAW files. I did not fabricate measurements or alter the pending matrix record. OK passes (only the pre-existing unknown pickup-runner model warning). Returning LUMO-118 to review for human scheduling/provisioning of the capture session.


### Comment — claude @ 2026-09-02T00:40:41.048Z

Counterpoint verification (independent re-review of the codex implementation-agent's 'no code change can satisfy this' finding), HEAD 90c1b95.

CONFIRMED — genuine unresolved blocker, not fabricatable from this checkout:
- docs/PERFORMANCE_CAPTURE_MATRIX_2026-09-01.md still has zero archived rows: all STD-* rows read "pending local Release run"; all RAW24-*/RAW40-60-* rows read "requires licensed local RAW". The 'Current checkout record' section still states captures are pending.
- No RAW fixtures anywhere in the repo outside .build: `find . -iname '*.dng' -o -iname '*.cr2' -o -iname '*.cr3' -o -iname '*.nef' -o -iname '*.arw'` returns nothing; no realworldtest/ directory exists.
- `ioreg -c IODisplayConnect` reported 0 connected displays in this verification session (despite a logged-in console user per `who`), consistent with the prior agent's finding that this cannot be driven headlessly.
- xctrace is present but there is no CLI/agent path to drive the live app UI through every Light/Adjust/Effects control per matrix row, or to drive an Instruments Points-of-Interest + Metal System Trace recording, without a human operator.

No maintainability/security/performance issues found in the surrounding infrastructure (LUMO-117's benchmarks and matrix doc) during this pass — the gap is exclusively the archived-data rows this ticket exists to close, and closing it requires a human with a Release build, a real display, and licensed 24 MP / 40-60 MP RAW files.

Action taken per verification policy for an unresolved blocker: filed LUMO-119 (priority urgent, label verification, scoped to provisioning/running the human capture session) as a dependency of this ticket (LUMO-118 depends_on LUMO-119). No source or doc changes made — the pending-state matrix record is accurate and should not be altered until real captures exist. Returning LUMO-118 to review; do not re-dispatch to an implementation agent until LUMO-119's human capture session is scheduled/completed.

## Agent log

- 2026-09-02T02:26:27.202Z: Completed with the reduced scope: automated Release xctrace capture of DSC07826.ARW, durable summary, and explicit documentation of unrun exhaustive matrix combinations.
