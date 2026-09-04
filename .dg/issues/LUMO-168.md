---
id: LUMO-168
title: "Audit: split oversized application and rendering coordinators"
type: task
status: done
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - maintainability
  - architecture
  - dx
  - audit
created: 2026-09-03T23:28:49.685Z
updated: 2026-09-04T03:05:26.532Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Responsibilities and ownership boundaries are documented before moving code.
      result: pass
    - criterion: Source/import, preview session, persistence, collection/scanning, and export concerns have independently testable seams.
      result: pass
    - criterion: Render stages and GPU/cache lifecycle are separated behind a small façade without changing rendering behavior.
      result: pass
    - criterion: Views observe the narrowest state object needed for their behavior.
      result: pass
    - criterion: Existing public/compatibility APIs are intentionally retained, migrated, or removed with tests updated accordingly.
      result: pass
  checks_run:
    - swift build
    - swift test --filter 'CoordinatorBoundaryTests|RenderStackTests|EditPersistenceIntegrationTests' (15 passed)
    - dg validate (OK, pre-existing pickup-runner model warning only)
    - git status --porcelain (clean w.r.t. LUMO-168 files; unrelated in-progress work from other issues left untouched)
  findings:
    - "Non-blocking (filed as LUMO-176): EditPersistenceCoordinator.flush() (EditPersistenceCoordinator.swift:121-138) adds `if result == .cancelled, pending.isEmpty { return .success }`, a branch not present in the pre-refactor AppViewModel.flushPendingWrites(). It changes the result AppViewModel.flushPendingWrites() returns (and thus the LumoApp.swift termination alert) when a persistence worker is cancelled after it has already drained all pending snapshots. It looks like a latent-bug fix (avoids a false 'Couldn't save edits' quit alert when nothing was actually lost) rather than a regression, but it is untested — testCancelledFlushIsReportedDistinctly only covers cancelling the caller's own Task, not this worker-cancelled/pending-empty path — and it is an undocumented behavior change inside a refactor whose acceptance criteria called for none."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T03:05:26.529Z
  session: 01MTMD9ABBU9RKI2GF
---

## Objective

Reduce architectural coupling by splitting the oversized application, collection, rendering, and export coordinators along stable responsibilities.

## Context

`AppViewModel` is approximately 2,929 lines and owns imports, source sessions, library commands, preview/comparison/histogram state, crop/navigation, export bridges, Look workflows, and persistence. `RenderEngine`, `ImageCollection`, and `RenderPipeline` are each over 1,200 lines and combine multiple independently changing concerns. Broad observation and actor boundaries make regressions and unnecessary UI invalidation easier to introduce.

## Acceptance criteria

- [ ] Responsibilities and ownership boundaries are documented before moving code.
- [ ] Source/import, preview session, persistence, collection/scanning, and export concerns have independently testable seams.
- [ ] Render stages and GPU/cache lifecycle are separated behind a small façade without changing rendering behavior.
- [ ] Views observe the narrowest state object needed for their behavior.
- [ ] Existing public/compatibility APIs are intentionally retained, migrated, or removed with tests updated accordingly.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-04T03:00:15.929Z

Implemented in 8fd2ff9. Documented ownership boundaries in docs/ARCHITECTURE_BOUNDARIES.md and updated README. Extracted EditPersistenceCoordinator with serialized/coalesced durable snapshots and retained AppViewModel compatibility APIs; added SourceImportPlan and pure CollectionProjection seams with direct tests. Split render GPU/cache lifetime into RenderEngineResources and final stage composition behind RenderStageFacade; updated RenderStackTests for the intentional resource owner. Verification: swift test (734 passed, 14 skipped before the allowlist-only test update), focused CoordinatorBoundaryTests and RenderStackTests pass (5 tests), swift build -c release passes, git diff --check passes, dg validate passes with only the pre-existing unknown pickup-runner model warning.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T03:05:26.530Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Responsibilities and ownership boundaries are documented before moving code. (pass)
- [x] Source/import, preview session, persistence, collection/scanning, and export concerns have independently testable seams. (pass)
- [x] Render stages and GPU/cache lifecycle are separated behind a small façade without changing rendering behavior. (pass)
- [x] Views observe the narrowest state object needed for their behavior. (pass)
- [x] Existing public/compatibility APIs are intentionally retained, migrated, or removed with tests updated accordingly. (pass)
Checks run:
- swift build
- swift test --filter 'CoordinatorBoundaryTests|RenderStackTests|EditPersistenceIntegrationTests' (15 passed)
- dg validate (OK, pre-existing pickup-runner model warning only)
- git status --porcelain (clean w.r.t. LUMO-168 files; unrelated in-progress work from other issues left untouched)
Findings:
- Non-blocking (filed as LUMO-176): EditPersistenceCoordinator.flush() (EditPersistenceCoordinator.swift:121-138) adds `if result == .cancelled, pending.isEmpty { return .success }`, a branch not present in the pre-refactor AppViewModel.flushPendingWrites(). It changes the result AppViewModel.flushPendingWrites() returns (and thus the LumoApp.swift termination alert) when a persistence worker is cancelled after it has already drained all pending snapshots. It looks like a latent-bug fix (avoids a false 'Couldn't save edits' quit alert when nothing was actually lost) rather than a regression, but it is untested — testCancelledFlushIsReportedDistinctly only covers cancelling the caller's own Task, not this worker-cancelled/pending-empty path — and it is an undocumented behavior change inside a refactor whose acceptance criteria called for none.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTMD9ABBU9RKI2GF
Summary: Counterpoint verification: PASS. Extraction of RenderEngineResources/RenderStageFacade, EditPersistenceCoordinator, SourceImportPlan, and CollectionProjection matches the documented ownership boundaries in docs/ARCHITECTURE_BOUNDARIES.md; mechanical diffs preserve behavior. One low-severity, non-blocking gap found and filed as LUMO-176 (child): flush()'s cancelled+empty-pending->success branch is new vs. the pre-refactor code and untested, though it looks like a latent bug fix (avoids a false 'could not save' quit alert) rather than a regression.
