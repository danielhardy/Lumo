---
id: LUMO-004
title: Establish the post-rename build and regression baseline
type: task
status: done
priority: urgent
labels:
  - mvp
  - epic:identity
  - phase:0
created: 2026-08-30T18:30:18.315Z
updated: 2026-08-31T02:58:10.419Z
depends_on:
  - LUMO-002
  - LUMO-003
estimate: 3
order: t
board: product
---

## Objective

Prove the rename preserved behavior and record the exact build, test, and capability baseline future tickets must protect.

## Context

Part of **Epic 0 — Product identity and clean baseline**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Run debug build, full tests, and release build.
- Triage only rename-related failures.
- Document retained inherited capabilities and known pre-existing gaps without broad cleanup.

## Acceptance criteria

- [ ] Debug build, full tests, and release build are green on the supported toolchain.
- [ ] A concise baseline record names test count, toolchain, retained capabilities, and known gaps.
- [ ] CI uses the renamed schemes/targets and remains green.

## Verification

- Run swift build, swift test, and swift build -c release.
- Inspect CI configuration for stale target names.

## Out of scope

- Fixing unrelated legacy defects.
- Performance tuning.

### Comment — codex @ 2026-08-31T02:55:05.688Z

Implemented and verified the post-rename baseline in commit e14b03c. Added docs/BUILD_BASELINE.md and linked it from README.md.

Verification: Swift 6.3.3, Xcode 26.6, macOS 26.5 SDK, arm64 deployment target macOS 14. `swift build` passed; `swift test` passed with 308 test cases, 20 expected environment-gated skips, and 0 failures; `swift build -c release` passed. CI has no stale LUTzy/LUTzyKit references and already runs the renamed SwiftPM package through debug build, tests, and release build. No rename-related code failures were found.

### Comment — claude @ 2026-08-31T02:58:08.600Z

## Verification report (independent counterpoint review)

Status: PASS — no blockers, no localized fixes needed.

Re-ran all three commands declared in the issue's Verification section from a clean worktree on this branch:

- `swift build`: passed.
- `swift test`: 308 tests, 20 skipped, 0 failures — matches the claimed baseline exactly.
- `swift build -c release`: passed.

Toolchain observed: Swift 6.3.3, arm64-apple-macosx26.0 target — consistent with the recorded Xcode 26.6 / macOS 26.5 SDK baseline.

Checked CI (.github/workflows/ci.yml): runs on macos-26, uses the renamed SwiftPM package with no stale LUTzy/LUTzyKit target or scheme references, and executes debug build → test → release build as required.

Checked docs/BUILD_BASELINE.md: present, linked from README.md, and its stated toolchain/test-count/retained-capabilities/known-gaps content matches what was independently reproduced.

git status --porcelain clean of tracked-file changes (only pre-existing untracked .dg/ directory). No code changes required; this was a read-only verification pass.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
