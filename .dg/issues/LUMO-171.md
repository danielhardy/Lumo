---
id: LUMO-171
title: "Audit: coalesce and cancel stale Look thumbnail renders"
type: task
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - performance
  - rendering
  - look
  - audit
created: 2026-09-03T23:31:00.000Z
updated: 2026-09-04T04:22:15.543Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Newer requests for the same source/Look replace or supersede older queued work.
      result: pass
      notes: LookPreviewCoordinator coalesces by source fingerprint, LUT fingerprint, and viewport; a newer document generation cancels the prior logical slot before admission.
    - criterion: SwiftUI task cancellation propagates through the scheduler to the render operation.
      result: pass
      notes: Scheduler terminal callbacks cover cancellation and eviction, and Look preview task cancellation calls scheduler.cancel so queued and running operations terminate through one contract.
    - criterion: Look thumbnails refresh at an intentional edit cadence rather than every transient pointer tick.
      result: pass
      notes: Thumbnail admission waits 60 ms, matching the existing editor quiet period; a 12-generation burst produced no early render and one final render in tests.
    - criterion: Preview generation uses a direct image/texture path without unnecessary encode/decode work.
      result: pass
      notes: LookPreviewCoordinator calls RenderEngining.makeCGImage; the production RenderEngine creates CGImage beside its CIContext without PNG encode/decode.
    - criterion: Tests or instrumentation demonstrate bounded stale work while dragging and scrolling.
      result: pass
      notes: Focused tests cover direct rendering, cancellation retry, latest-generation supersession, terminal outcomes, queue depth, and rapid-generation cadence.
  checks_run:
    - swift test (738 passed, 32 expected skips)
    - swift test --filter LookPreviewTests|ImageWorkSchedulerTests (18 passed)
    - scripts/check-swift-format.sh (passed)
    - git diff --check (passed)
    - dg validate (OK; pre-existing unknown pickup-runner model warning and unrelated LUMO-175 context warning)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T04:22:15.538Z
  session: 01MTMFPQCJZ164YRNA
---

## Objective

Coalesce and cancel stale Look-thumbnail renders so rapid edits and scrolling do not starve active editor work.

## Context

Look-preview task identity changes with every document revision, but each scheduler request receives a unique job ID. SwiftUI task cancellation does not reliably cancel the queued scheduler job, and each thumbnail takes an encoded-raster round trip before becoming a `CGImage`. Slider dragging can therefore create a render storm of obsolete work.

## Acceptance criteria

- [ ] Newer requests for the same source/Look replace or supersede older queued work.
- [ ] SwiftUI task cancellation propagates through the scheduler to the render operation.
- [ ] Look thumbnails refresh at an intentional edit cadence rather than every transient pointer tick.
- [ ] Preview generation uses a direct image/texture path without unnecessary encode/decode work.
- [ ] Tests or instrumentation demonstrate bounded stale work while dragging and scrolling.

## Implementation notes

Coordinate with LUMO-165 so cancellation and eviction have one terminal-result contract. Preserve latest-wins behavior for source and document generations.

## Agent log

- 2026-09-04T04:22:15.541Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Newer requests for the same source/Look replace or supersede older queued work. (pass) — LookPreviewCoordinator coalesces by source fingerprint, LUT fingerprint, and viewport; a newer document generation cancels the prior logical slot before admission.
- [x] SwiftUI task cancellation propagates through the scheduler to the render operation. (pass) — Scheduler terminal callbacks cover cancellation and eviction, and Look preview task cancellation calls scheduler.cancel so queued and running operations terminate through one contract.
- [x] Look thumbnails refresh at an intentional edit cadence rather than every transient pointer tick. (pass) — Thumbnail admission waits 60 ms, matching the existing editor quiet period; a 12-generation burst produced no early render and one final render in tests.
- [x] Preview generation uses a direct image/texture path without unnecessary encode/decode work. (pass) — LookPreviewCoordinator calls RenderEngining.makeCGImage; the production RenderEngine creates CGImage beside its CIContext without PNG encode/decode.
- [x] Tests or instrumentation demonstrate bounded stale work while dragging and scrolling. (pass) — Focused tests cover direct rendering, cancellation retry, latest-generation supersession, terminal outcomes, queue depth, and rapid-generation cadence.
Checks run:
- swift test (738 passed, 32 expected skips)
- swift test --filter LookPreviewTests|ImageWorkSchedulerTests (18 passed)
- scripts/check-swift-format.sh (passed)
- git diff --check (passed)
- dg validate (OK; pre-existing unknown pickup-runner model warning and unrelated LUMO-175 context warning)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTMFPQCJZ164YRNA
Summary: Look thumbnail work now uses stable source/Look scheduler slots, latest-wins cancellation, a 60 ms quiet cadence, and direct CGImage rendering; scheduler terminal outcomes complete cancellation eviction and rejection are propagated.
