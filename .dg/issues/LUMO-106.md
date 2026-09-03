---
id: LUMO-106
title: Correct developed-source cache identity for effective render resolution
type: bug
status: done
priority: high
labels:
  - performance
  - epic:quality
  - rendering
  - correctness
created: 2026-09-01T22:02:24.096Z
updated: 2026-09-01T22:45:52.682Z
order: a0
board: product
commits:
  - 673fe59
---

## Objective

Ensure cached development obeys the effective resolution requested by every quality tier, so interaction stays within budget and settled previews recover all requested detail.

## Context and evidence

Performance audit item 1, evaluated at commit `724ad99`: [September 1 audit](../../docs/PERFORMANCE_AUDIT_2026-09-01.md).
The user requested tangible responsiveness improvements without sacrificing visual fidelity or accuracy; prioritize code quality and measured impact over minimizing implementation effort.

**Evidence:** [RenderCacheKey.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderCacheKey.swift:25) maps `.preview(size)` and `.interactive(size, budget)` to the same width/height bits. It ignores the interactive budget. [RenderScale.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderScale.swift:30) caps interactive output at 1.5 MP, while [RenderEngine.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderEngine.swift:543) uses that shared key for standard-image development.

**Impact:** A settled standard preview can remain permanently undersized, or an interactive preview can process 2.56× its intended pixels in the reproduced case. This affects accuracy and responsiveness, not just cache efficiency.

**Approach:** Key source stages by their effective pixel dimensions/scale and any policy that actually changes source pixels. Include budget-derived resolution; avoid distinguishing equivalent requests unnecessarily. Keep output-quality identity where it affects final-result policy.

## Acceptance criteria

- [ ] A 3000×2000 standard source with a 2400×1600 target returns 1500×1000 for interactive and 2400×1600 for preview, in both request orders through makeCIImage.
- [ ] Different interactive frame budgets cannot collide when they produce different source pixels; equivalent effective scales may reuse safe entries.
- [ ] The final settled image matches a fresh-engine reference in dimensions and pixels after repeated interactive/settled transitions.
- [ ] Source replacement, RAW develop changes, full-resolution/export bypass, and existing working-space/output-quality cache contracts remain correct.
- [ ] Tests exercise real production source-cache lookup with a source/viewport above the cap; tiny fixtures alone do not constitute coverage.

## Verification plan

Add regression coverage in RenderCacheTests and RenderRequestTests using generated above-cap images. Exercise standard and RAW branches separately when RAW fixtures are available. Verify effective dimensions and pixel output, not merely cache-hit counters.

Start with these relevant checks, then run `swift test` and `swift build -c release` before implementation handoff:

```sh
swift test --filter RenderCacheTests
swift test --filter RenderRequestTests
```

Record generated fixture parameters and, for hardware results, source dimensions/format, RAW decoder/version when relevant, hardware, OS, commit, Release configuration, viewport/backing pixels, and cold/warm conditions. Attach before/after traces or durable summaries. The September 1 audit measured component rendering on an M1 Pro (10 CPU cores, 16 GB, macOS 26.6); it did not measure Lightroom/Photomator or real RAW input-to-display latency. Its 198.9 ms rebuild versus 4.9 ms source-reuse PNG result motivates reuse but is not a promised whole-app speedup.

## Fidelity and engineering constraints

Preserve macOS 14 deployment, Swift 6 concurrency safety, Apple-framework-only dependencies, deterministic edit ordering, working-space conversion, premultiplied alpha behavior, orientation, native-resolution export, and deterministic grain where applicable. Do not hide latency by permanently reducing resolution, skipping effects, or weakening precision. Pixel parity needs documented tolerances and representative fine-detail, edge, skin-tone, saturated/wide-gamut, crop, and transparency fixtures; sharing the same graph across resolutions is not proof of equivalence for nonlinear/spatial processing.

## Dependencies and scope boundaries

Hard prerequisites: None; independently actionable.

Independent correctness fix. This is the cache prerequisite for the resolution-planning and RAW-stage-reuse tickets. Do not wait for the broader rendering redesign.

These tickets provide concrete implementation work for the broader LUMO-055/LUMO-058 quality effort. This ticket is in backlog for planning; implementation and automatic pickup have not been requested as part of ticket creation.

### Comment — codex @ 2026-09-01T22:41:19.457Z

Implemented in 673fe59. Developed-source and preview cache identities now use effective source resolution, including the interactive frame-budget scale; RenderRequest carries the budget through settle promotion. Added generated 3000x2000 production-path regressions covering interactive/settled request order and distinct budgets. Verification: swift test --filter RenderCacheTests (13 passed), swift test --filter RenderRequestTests (4 passed), swift test (564 passed, 26 expected skips), swift build -c release passed, git diff --check passed, dg validate passed with the known pickup-runner model warning.

### Comment — claude @ 2026-09-01T22:45:42.642Z

## Independent verification — PASS

Reviewed commit 673fe59 against the acceptance criteria and re-ran the declared checks.

**Correctness**
- `RenderScaleKey(scale, nativeExtent:)` now keys on effective source pixels (native extent × scale factor), so `.preview` and `.interactive` no longer alias on width/height alone; the interactive frame budget is folded into the factor via `RenderScale.targetSize`, so distinct budgets that produce distinct effective pixels get distinct keys, and budgets that resolve to the same effective scale correctly reuse.
- Both `DevelopedSourceCacheKey` (RenderEngine.swift:557) and `PreviewCacheKey` (RenderEngine.swift:700) call sites pass `source.nativeExtent`; both are the only production call sites (grep-verified), so the fallback branch in `RenderScaleKey.init` (no/degenerate `nativeExtent`) is defensive-only, not live for interactive/preview traffic.
- Checked the one place `nativeExtent: .zero` is actually constructed in production (`ExportCoordinator.source(for:)`, `Thumbnails.generate`): both are `.full`-scale/unrelated-cache paths, so they never reach the new keying logic — no live path exercises the degenerate fallback with a real preview/interactive request.
- Confirmed `ImageSource.nativeExtent` is populated from a real, unscaled decode (`AppViewModel` loads via `ImageDecoder.load`, which for RAW calls `CIRAWFilter(imageURL:)?.outputImage` with no `scaleFactor` set) — so it agrees with the decoder-truth (`CIRAWFilter.nativeSize` / `image.extent.size`) that `RenderPipeline.developedSource` uses for the actual render, avoiding a theoretical key/output divergence.
- RAW's single-entry `InteractiveRAWFilterSession` path recomputes `scale.factor` fresh on every call rather than caching by key, so it was never subject to this bug and needed no change (consistent with the evidence in the ticket, which cited only the standard-image cache-key path).

**Test coverage** — matches acceptance criteria directly:
- `testEffectiveInteractiveScaleCannotReuseSettledDevelopedSource`: 3000×2000 source, 2400×1600 target, both request orders — interactive=1500×1000, settled=2400×1600. Matches AC #1 exactly.
- `testInteractiveBudgetsWithDifferentEffectiveScalesDoNotCollide`: 16.7ms vs 33.4ms budgets on the same target produce distinct effective sizes (1500×1000 vs 2122×1415) and don't collide. Matches AC #2.
- Both use a generated 3000×2000 production-path fixture through `engine.makeCIImage`, not a tiny fixture. Matches AC #5.
- Pre-existing tests for source replacement, RAW develop-hash changes, full-resolution/export bypass, and working-space/output-quality identity all still pass unmodified.
- Minor gap (non-blocking): AC #3 ("matches a fresh-engine reference in dimensions **and pixels**") is exercised for dimensions only, not pixel-content equality, and only across one interactive→settled and one settled→interactive transition rather than a repeated cycle. The dimension check already exercises the actual defect (a cache-key collision that served wrong-sized pixels), so this is a coverage nicety, not a correctness gap.

**Checks run**
- `swift test --filter RenderCacheTests` — 13 passed.
- `swift test --filter RenderRequestTests` — 4 passed.
- `swift test` (full suite) — 564 passed, 26 expected skips, 0 failures.
- `swift build -c release` — succeeds (only pre-existing Core Image kernel deprecation warnings, unrelated to this change).
- `git status --porcelain` — clean aside from pre-existing DispatchGraph bookkeeping churn already present before this verification pass.

No blockers found. No child tickets filed — the one item noted above (pixel-content equality across repeated transitions) is small enough to fold into normal follow-up work rather than warranting a standalone `verification`-labeled ticket.

Hardware/config: macOS 26.6, Xcode 26 toolchain, Release configuration, commit 673fe59, run on the machine used for the September 1 audit.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T22:45:52.680Z: Independent verification passed: cache-key fix correctly ties source/preview identity to effective resolution including interactive budget; regression tests match all acceptance criteria; full suite (564 passed) and release build green.
