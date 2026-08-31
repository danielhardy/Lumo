---
id: LUMO-014
title: Add bounded thumbnail, developed-source, and preview caches
type: task
status: done
priority: high
labels:
  - mvp
  - epic:rendering
  - phase:2
created: 2026-08-30T18:30:21.697Z
updated: 2026-08-31T13:48:51.698Z
depends_on:
  - LUMO-012
estimate: 5
order: a0
board: product
commits:
  - d45ca6d451bc62f100b2725b0d3d2d4e304372c8
---

## Objective

Implement measurable bounded caches for expensive reusable intermediates without stale pixels or unbounded memory growth.

## Context

Part of **Epic 2 — Render orchestration, caching, and observability**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Define cache keys including source identity/fingerprint, document hash, render size/quality, working color space, and pipeline version as appropriate.
- Set cost/count limits and memory-pressure eviction.
- Keep full-resolution export out of inappropriate final-image caching.
- Expose hit/miss counters for instrumentation.

## Acceptance criteria

- [ ] Repeated identical preview requests hit cache.
- [ ] Any material source/edit/size/pipeline change misses.
- [ ] Memory pressure and configured limits evict entries.
- [ ] A long navigation session has bounded cache memory.

## Verification

- Add key-completeness, eviction, invalidation, and hit/miss tests.

## Out of scope

- Persistent cloud cache.
- Premature disk cache unless measurement justifies it.

### Comment — codex @ 2026-08-31T13:44:07.341Z

Implemented bounded thumbnail, developed-source, and preview caches in commit a13fa6a (with prerequisite LUMO-012 request API in 3b7d4dc). Added source/document/size/quality/working-space/pipeline cache keys, exact thumbnail content fingerprints and URL change fingerprints, LRU count and byte limits, memory-pressure and explicit invalidation purges, cache hit/miss/eviction statistics, and full-resolution/export bypasses for final-image caching. Added key-completeness, hit/miss, invalidation, source-change, eviction, memory-pressure, and thumbnail tests. Verification: swift test passed (322 tests, 20 expected skips, 0 failures); swift build -c release passed; git diff --check passed; dg validate passed with only pre-existing warnings.

### Comment — claude @ 2026-08-31T13:48:47.447Z

Verification report (counterpoint pass, independent of human review)

Scope reviewed: BoundedCache.swift, RenderCacheKey.swift, ImageSource.swift, RenderEngine.swift, RenderPipeline.swift, RenderScale.swift, CubeLUT.swift, Thumbnails.swift, RenderCacheTests.swift (commits 3b7d4dc, a13fa6a).

Findings and dispositions:
1. [Fixed, commit f7ad446] Thumbnails.generate(from url:) read the entire file into memory (Data(contentsOf:)) on every call just to compute the cache key, including cache hits. For large RAWs (tens of MB) this defeats the embedded-preview fast path the cache exists to preserve, and was not caught by tests because fixtures are tiny. Replaced with a nanosecond-precision stat(2) fingerprint (device/inode/size/mtime/ctime), matching the approach ImageSource.cacheFingerprint already uses for URL-backed sources — same change-detection guarantee, no content read.
2. [Fixed, commit d45ca6d] RenderCacheHash.digest(_:Encodable) fell back to a fixed "encoding-failed" string when JSONEncoder threw (e.g. a non-conforming Double such as .nan reaching RAWDevelopSettings/EditDocument). Two different documents that both fail to encode would then collide on the same preview/developed-source cache key, risking one serving the other's rendered pixels. Fallback now mints a fresh UUID per failure so a failed encode always misses instead of risking a false hit. Low likelihood in practice (requires a NaN/Infinity Double to reach an encoded field) but cheap and correctness-relevant to close.
3. No blockers found. Cache key completeness (source fingerprint, document hash inc. rawDevelop, LUT fingerprint+content, scale, quality, working space, pipeline version), LRU eviction, memory-pressure purge, and full-resolution/export bypass all check out against the acceptance criteria and are exercised by RenderCacheTests.

Verification commands run after fixes:
- swift test — 322 tests, 20 expected skips, 0 failures
- swift build -c release — passed
- git diff --check — clean
- dg validate — OK (only pre-existing unrelated warnings: agents.pickup.runner model name, LUMO-011 context completeness)

Both fixes are localized, non-behavioral (no API/schema change), and covered by the existing cache test suite, which still passes unmodified.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-08-31T13:48:51.696Z: Independent verification pass: fixed a thumbnail-cache performance regression (full-file read on every call) and a cache-key collision risk on encoding failure. 322 tests pass, release build clean, dg validate OK.
