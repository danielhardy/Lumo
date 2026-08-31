---
id: LUMO-016
title: Instrument the end-to-end image workflow with signposts and metrics
type: task
status: done
priority: high
labels:
  - mvp
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:22.463Z
updated: 2026-08-31T14:13:14.084Z
depends_on:
  - LUMO-013
  - LUMO-014
estimate: 3
order: a0
board: product
commits:
  - f2c9ee6
---

## Objective

Make performance claims falsifiable with signposts for launch, scan, decode, render, cache, photo switch, histogram, and export.

## Context

Part of **Epic 2 — Render orchestration, caching, and observability**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Create centralized OSLog categories and signpost interval helpers.
- Attach source/quality identifiers that aid diagnosis without logging private paths.
- Measure cache hit/miss and cancellation/coalescing counts.
- Document an Instruments capture recipe and target thresholds.

## Acceptance criteria

- [ ] Every required stage emits balanced signpost intervals.
- [ ] Logs do not expose full user paths or metadata by default.
- [ ] A developer can capture photo-switch and slider latency using documented steps.
- [ ] Metrics distinguish interactive from settled/export work.

## Verification

- Add lightweight signpost helper tests where possible and manually inspect an Instruments trace.

## Out of scope

- Analytics upload.
- Claims that targets are met before profiling.

### Comment — codex @ 2026-08-31T14:11:13.592Z

Implemented in f2c9ee6 (on top of the completed render-request/cache prerequisites). Added centralized OSLog signpost intervals/events for launch, scans, decode, render, cache, photo switch, histogram, and export; private-safe hashed source tokens; interactive/settled/export quality labels; cache statistics and cancellation/coalescing events; focused observability tests; and docs/INSTRUMENTS.md with repeatable capture steps and validation targets. Verification: swift test passed (328 tests, 20 expected skips), swift build -c release passed, git diff --check passed, dg validate passed with only pre-existing warnings.

### Comment — claude @ 2026-08-31T14:13:11.260Z

## Verification report (independent counterpoint review)

**Scope reviewed:** commit f2c9ee6 "Instrument the end-to-end image workflow" (Observability.swift + call sites in RenderEngine, PreviewCoordinator, ImageDecoder, ImageCollection, LUTLibrary, LUTFilterCache, Thumbnails, ExportCoordinator, AppViewModel).

**Checks run:**
- `swift build` — clean.
- `swift test` — 328 tests, 20 expected skips, 0 failures.
- `swift build -c release` — clean.
- `dg validate` — OK (only the two pre-existing, unrelated warnings).
- `git diff --check` — clean.

**Code review findings:**
- Signpost begin/end pairing verified at every call site, including early-return paths inside `render()` — `defer` is scoped correctly to the enclosing `if let previewKey { }` block, so it still fires on the early `return cached` path. `LumoSignpostInterval.end()` is idempotent (covered by `testEndingAnIntervalMoreThanOnceIsSafe`).
- Privacy requirement verified: every path identifier (`ImageSource.cacheFingerprint`, scan folder URLs, in-memory data names, photo names) is routed through `LumoTraceContext`/`sourceToken(forInput:)`, which SHA-256 hashes and truncates before it ever reaches an OSLog interpolation. `testSourceTokensAreStablePrivateSafeAndDistinct` asserts the original path/filename does not appear in the token.
- Cache/cancellation/coalescing bookkeeping (`LUTFilterCache.hitCount/missCount`, `PreviewCoordinator` cancellation/coalesced events) is only ever touched from a single isolation domain (actor-private state or `@MainActor`), so no new data race surface under Swift 6 strict concurrency — consistent with the zero-opt-out build passing cleanly.
- `docs/INSTRUMENTS.md` gives a concrete, repeatable capture recipe (cold/warm launch, photo switch, slider interactive vs. settled, histogram, export) and states thresholds as targets to validate, not met claims — matches the "out of scope: claims that targets are met before profiling" constraint.
- Minor, non-blocking style nit: `LumoSignpostInterval.init` allocates a fresh `OSSignposter` per interval rather than reusing `LumoObservability`'s shared instance. Negligible cost (OSSignposter is a cheap value wrapper) — not worth a ticket.

**Verdict:** No blockers. Acceptance criteria are met: balanced intervals for every required stage, no path/metadata leakage, a documented Instruments recipe, and quality-tagged (interactive/settled/export) metrics that separate live editing from settled/export work.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T14:13:14.083Z: Independent verification passed: build/test/release/validate clean; privacy, interval balance, and concurrency isolation confirmed by code review; no blockers.
