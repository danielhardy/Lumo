---
id: LUMO-111
title: Reuse unchanged RAW output and expensive processing prefixes
type: task
status: done
priority: high
labels:
  - performance
  - epic:quality
  - raw
  - rendering
  - cache
created: 2026-09-01T22:05:10.899Z
updated: 2026-09-02T03:04:45.737Z
depends_on:
  - LUMO-106
  - LUMO-114
order: z1
board: product
commits:
  - 68ab886
---

## Objective

Avoid reconfiguring RAW development and rebuilding unchanged upstream processing when the user changes only downstream adjustments.

## Context and evidence

Performance audit item 6, evaluated at commit `724ad99`: [September 1 audit](../../docs/PERFORMANCE_AUDIT_2026-09-01.md).
The user requested tangible responsiveness improvements without sacrificing visual fidelity or accuracy; prioritize code quality and measured impact over minimizing implementation effort.

**Evidence:** [RenderEngine.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderEngine.swift:549) sends every interactive RAW request through `InteractiveRAWFilterSession.output`, even for downstream light/color/LUT changes. That method restores all baseline values, reapplies settings, writes scale, and requests `outputImage` every time. [RenderPipeline.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderPipeline.swift:92) reconstructs the full downstream graph. The final preview cache belongs to the encoded `render` path, not `makeCIImage`.

**Impact:** Keeping the CIRAWFilter alive avoids construction but does not explicitly reuse unchanged output or completed upstream processing. RAW property writes may invalidate expensive decoder work; the exact cost must be measured with actual RAW files.

**Approach:** Memoize the RAW output by source revision, develop settings, and effective scale. Apply only changed decoder properties, including correct restoration of optional defaults. Introduce bounded caches at measured expensive stage boundaries, with downstream-only invalidation. In particular, changing LUT intensity or grain should reuse unchanged development and earlier spatial effects.

## Acceptance criteria

- [ ] With unchanged source/develop settings/effective scale, Light, Color, LUT, and Grain interaction reuses RAW output without resetting the filter or requesting fresh output per event.
- [ ] A changed decoder property invalidates only the appropriate cached output; optional settings returning to nil restore the captured decoder default correctly.
- [ ] Cache identity includes source revision, effective scale, relevant upstream settings, working-space dependencies, LUT content identity, and pipeline version as applicable.
- [ ] Measured expensive processing prefixes are reused with downstream-only invalidation; no blanket materialization of every node that defeats Core Image fusion.
- [ ] Cached results match fresh-pipeline pixels, alpha, deterministic grain, crop geometry, and native export behavior across source replacement and resets.
- [ ] GPU resources and decoded-byte estimates have explicit budgets, overflow-safe accounting, eviction, and in-flight ownership; sustained editing/navigation has bounded retained resources.
- [ ] Publish before/after CPU configuration/graph time, GPU evaluation time, allocation/upload bytes, and p95 input-to-present for real RAW files; do not infer a RAW speedup from fake renderers.

## Verification plan

Extend RenderCacheTests, RAWDevelopSettingsTests, RenderEngineTests, and effects/color parity coverage. Instrument decoder construction/property writes/output requests and actual GPU work separately. Test multiple camera decoders, source replacement, default resets, memory pressure, and repeated LUT/grain drags.

Start with these relevant checks, then run `swift test` and `swift build -c release` before implementation handoff:

```sh
swift test --filter RenderCacheTests
swift test --filter RAWDevelopSettingsTests
swift test --filter RenderEngineTests
```

Record generated fixture parameters and, for hardware results, source dimensions/format, RAW decoder/version when relevant, hardware, OS, commit, Release configuration, viewport/backing pixels, and cold/warm conditions. Attach before/after traces or durable summaries. The September 1 audit measured component rendering on an M1 Pro (10 CPU cores, 16 GB, macOS 26.6); it did not measure Lightroom/Photomator or real RAW input-to-display latency. Its 198.9 ms rebuild versus 4.9 ms source-reuse PNG result motivates reuse but is not a promised whole-app speedup.

## Fidelity and engineering constraints

Preserve macOS 14 deployment, Swift 6 concurrency safety, Apple-framework-only dependencies, deterministic edit ordering, working-space conversion, premultiplied alpha behavior, orientation, native-resolution export, and deterministic grain where applicable. Do not hide latency by permanently reducing resolution, skipping effects, or weakening precision. Pixel parity needs documented tolerances and representative fine-detail, edge, skin-tone, saturated/wide-gamut, crop, and transparency fixtures; sharing the same graph across resolutions is not proof of equivalence for nonlinear/spatial processing.

## Dependencies and scope boundaries

Hard prerequisites: LUMO-106, LUMO-114

Depends on effective scale keys and accurate telemetry. Owns decoder/session reuse and processing-stage invalidation. Completed GPU texture ownership is coordinated with the presentation ticket; both must share one documented resource contract.

These tickets provide concrete implementation work for the broader LUMO-055/LUMO-058 quality effort. This ticket is in backlog for planning; implementation and automatic pickup have not been requested as part of ticket creation.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T03:04:45.732Z: Implemented actor-local interactive RAW output memoization with source/develop/effective-scale keys, changed-property-only decoder updates and baseline restoration; added bounded half-float materialized pre-LUT prefix reuse for downstream LUT/crop/vignette/grain edits; added overflow-safe cache accounting, work counters, invalidation, memory-pressure eviction, and parity/eviction/RAW regression coverage. Focused suites and release build pass; full suite retains three pre-existing realworldtest fixture failures.
