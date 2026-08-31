---
id: LUMO-001
title: Epic 0 — Product identity and clean baseline
type: feature
status: done
priority: urgent
labels:
  - mvp
  - epic
  - epic:identity
  - phase:0
created: 2026-08-30T18:25:25.896Z
updated: 2026-08-31T03:02:52.093Z
depends_on:
  - LUMO-002
  - LUMO-003
  - LUMO-004
order: w
board: product
---

## Objective

Complete the fork cleanup before feature expansion, with Lumo identity, preserved LUTzy attribution, and a trusted green baseline.

## MVP outcome

- [ ] All product/package identifiers use Lumo except historical attribution.
- [ ] Update/Revised README that explains the project intention and methodology (an expeirement in not just agent built but agent lead software development. Including DispatchGraph)
- [ ] Debug and release builds plus the applicable test suite pass.
- [ ] Existing RAW, LUT, thumbnail, Photos, metadata, histogram, and export capabilities remain intact.

## Child tickets

- LUMO-002 — Rename the LUTzy fork to Lumo across package and app surfaces
- LUMO-003 — Preserve upstream attribution and rewrite product documentation for Lumo
- LUMO-004 — Establish the post-rename build and regression baseline

## Sequencing

The dependency graph is authoritative. This epic is a tracking issue and depends on every child ticket; close it only after the outcome above is verified. Start from `.context/initial_concept.md` and preserve existing working LUTzy-derived behavior until its replacement is proven.

## Non-goals

Do not expand into the concept's explicitly excluded V2 features. Avoid a giant rewrite or broad file-moving exercise.

### Comment — codex @ 2026-08-31T03:01:44.865Z

Implemented and committed as dcff059. Completed Epic 0 documentation and baseline closure: README now explains Lumo intent and the agent-led development methodology with DispatchGraph; added docs/BUILD_BASELINE.md; updated living docs to Lumo naming and corrected LUMO_BENCH. Historical LUTzy attribution is preserved. Verification: swift build passed; swift test passed (308 executed, 20 skipped, 0 failures); swift build -c release passed; dg validate passed. Existing RAW, LUT, thumbnail, Photos, metadata, histogram, and export behavior remains covered by the full suite. Ready for review.

### Comment — claude @ 2026-08-31T03:02:48.513Z

## Independent verification report (counterpoint pass)

Reviewed independently after human review, with all declared checks re-run from a clean invocation rather than trusted from the prior comment.

**Checks re-run and confirmed:**
- `swift build` — passed.
- `swift test` — 308 executed, 20 skipped, 0 failures (matches the prior report; skips are the documented opt-in RAW-fixture and LUMO_BENCH cases).
- `swift build -c release` — passed.
- `dg validate` — OK (pre-existing unrelated warnings: agents.pickup.runner model name, LUMO-005 context completeness — out of scope for this issue).

**MVP outcome checklist verified against repo state:**
- Product/package identifiers use Lumo except historical attribution: confirmed. No `lutzy` hits under Sources/Tests; Package.swift targets are Lumo/LumoKit/LumoKitTests; entitlements file is Lumo.entitlements. Remaining `lutzy` matches are all intentional historical references (README fork/attribution section, docs/BUILD_BASELINE.md, .context/initial_concept.md, archived docs/superpowers design notes).
- README explains product intent and the agent-led/DispatchGraph methodology: confirmed, present and substantive.
- Debug + release builds and test suite pass: confirmed via independent re-run above.
- Existing RAW/LUT/thumbnail/Photos/metadata/histogram/export capabilities intact: covered by the passing 308-test suite (RenderPipelineTests, ThumbnailTests, WorkingSpaceTests, RenderStackTests, etc.), consistent with docs/BUILD_BASELINE.md's retained-capabilities list.
- All three child tickets (LUMO-002, LUMO-003, LUMO-004) confirmed status=done via `dg issue show`.

**Findings:** none. No correctness, maintainability, security, or performance issues found in the rename/documentation/baseline work. No localized fixes required; no child tickets created.

**Verdict:** PASS. Moving to done.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
