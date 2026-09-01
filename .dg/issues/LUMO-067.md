---
id: LUMO-067
title: Make the tone curve interactive and real-time responsive on large RAW
type: task
status: done
priority: high
labels:
  - mvp
  - epic:light
  - performance
created: 2026-08-31T20:46:44.961Z
updated: 2026-08-31T22:36:18.448Z
depends_on:
  - LUMO-028
estimate: 5
order: a0
board: product
---

## Objective

Make the tone curve editor feel instantaneous: click to add, double-click to remove, and a preview that tracks the pointer in real time — with no perceptible lag even on 60 MP RAW photos.

## Context

Part of **Epic 4 — Photographic Light controls** follow-up work. The curve model (LUMO-027) and the first interactive editor in the Light inspector (LUMO-028) are done. Today, adding a point requires the 50% button and there is no removal gesture; drags update through the debounced document path, so preview responsiveness during a drag is not guaranteed. The render pipeline already runs stages at preview scale rather than full resolution — the work here is making that path genuinely real-time and wiring the missing gestures.

## Scope

- Click on the curve line to add a point at that input, sampling its output from the current curve.
- Double-click an interior point to remove it; endpoint handles stay fixed by `LightToneCurve` invariants.
- While a point is dragged, re-render the preview per frame with latest-wins coalescing: one in-flight render, stale requests cancelled or dropped — no queue buildup.
- Run a full-resolution render after the gesture settles so export/histogram catch up; preview and settled renders must agree within test tolerance.
- Coalesce each drag/add/remove gesture into a single undo step, keeping the existing bounded per-photo history.

## Acceptance criteria

- [ ] Clicking on the line adds a point at (input, curve(input)); double-click removes interior points only.
- [ ] Dragging a point updates the displayed preview in real time with no visible lag on a 60 MP-class RAW source.
- [ ] At most one in-flight preview render during a drag; superseded renders are cancelled, not queued.
- [ ] One undo step per completed gesture (drag, add, remove).
- [ ] Existing keyboard and accessibility actions on the curve editor keep working.

## Verification

- Model tests for click sampling, removal, and endpoint invariants.
- View-model tests for gesture coalescing (latest-wins renders, single undo step).
- Benchmark: drag a point with a 60 MP-class preview; report p50/p95 pointer-to-pixel latency and assert it stays within an interactive budget.

## Out of scope

- Per-channel (R/G/B) curves.
- Parametric curve regions.


### Comment — codex @ 2026-08-31T22:33:07.972Z

Implemented in commit 523a0a8. Added curve sampling on click, endpoint-safe interior removal, spatial graph gestures, curve drag interaction lifecycle, latest-wins single-active interactive rendering, gesture-scoped undo, and focused model/view-model/coalescing/latency benchmark coverage. Verification: swift test passed (424 tests, 22 expected environment skips); LUMO_BENCH=1 latency benchmark passed with p50 6.5 ms / p95 6.8 ms on the deterministic 60 MP-class request path; swift build -c release passed; git diff --check passed; dg validate passed with only the pre-existing runner-model warning.


### Comment — claude @ 2026-08-31T22:36:15.766Z

## Independent verification report (counterpoint agent)

**Scope reviewed**: commit 523a0a8 — LightAdjustments.swift (addingPoint/removingPoint), PreviewCoordinator.swift (in-flight latch + latest-wins pending slot), AppViewModel(+Light).swift wiring, LightInspectorView.swift gestures, and the added test coverage.

**Checks run and reproduced**:
- `swift test` — 424 tests, 22 expected environment skips, 0 failures.
- `LUMO_BENCH=1 swift test --filter testLargePreviewInteractiveLatencyBenchmark` — p50 6.6 ms / p95 6.9 ms on the deterministic 60 MP-class path (budget 50 ms), consistent with the reported p50 6.5 / p95 6.8.
- `swift build -c release` — succeeds.
- `git diff --check` on the commit — clean.
- `dg validate` — OK (pre-existing runner-model warning only, unrelated).

**Correctness analysis**:
- `LightToneCurve.addingPoint`/`removingPoint` correctly protect endpoints (`dropFirst().dropLast()` candidate set) and are covered by model tests including exact endpoint no-ops.
- `PreviewCoordinator`'s new `interactiveRenderInFlight`/`pendingInteractive` pair correctly enforces "at most one in-flight render, latest-wins": traced the interleavings for submit-during-render, endInteraction-during-render, and navigation-cancel-during-render — in each case the stale render's completion handler resets the in-flight flag and either drops or reschedules the pending value, and `isCurrent(token)` prevents a stale render from publishing. `RenderEngine` is an actor, so serialization is enforced independently of this bookkeeping too.
- Undo coalescing verified analytically against `EditHistory.beginGrouping/endGrouping` (a no-op group is not recorded since `endGrouping` guards on `start != document`), and confirmed by `testCurveAddAndRemoveEachUseOneUndoStep` / `testCurveDragCoalescesEveryTickIntoOneUndoStep`.
- Checked the double-click-to-remove gesture stacking (`DragGesture(minimumDistance: 0)` + `simultaneousGesture(SpatialTapGesture(count: 2))` on the same point handle): each tap of the double-click also fires the drag gesture's onChanged/onEnded, but since location doesn't move this produces a no-op grouped interaction (no document change, no undo entry, no render request) — confirmed via the grouping guard rather than just eyeballing it. Not a correctness bug.

**Non-blocking observation (not filed as a ticket — cosmetic, no observable effect)**: because the phantom drag recognitions on double-click still call `beginPreviewInteraction()`/`endPreviewInteraction()`, `endInteraction()` re-submits `latestRequest` as a settled render even when nothing changed. It's idempotent (same document, same revision bump) and not visible to the user, so it doesn't rise to a backlog item.

**Verdict**: PASS. Acceptance criteria are met, tests are real and reproduce the claimed numbers, no blocking correctness/concurrency/undo issues found.

## Agent log

- 2026-08-31T22:36:18.446Z: Independent verification passed: tests, benchmark, release build, and diff-check all reproduce; no blocking correctness or concurrency issues found.
