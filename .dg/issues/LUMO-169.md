---
id: LUMO-169
title: "Audit: restore repository and CI quality guardrails"
type: task
status: done
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ci
  - dx
  - quality
  - audit
created: 2026-09-03T23:28:50.102Z
updated: 2026-09-04T04:09:07.757Z
order: a0
board: product
commits:
  - "502e211"
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: README and living audit/spec documents match the current product name, architecture, and test counts.
      result: pass
      notes: README states 735 XCTest methods; grep of Tests/LumoKitTests/*.swift confirms 735 occurrences of func test. docs/CODE_REVIEW.md and docs/PHASE2_SPEC.md renamed LUTzy to Lumo and reconciled historical findings against the current architecture.
    - criterion: A checked-in Swift-format configuration matches the house style and CI reports actionable changed-file violations.
      result: pass
      notes: .swift-format is checked in; scripts/check-swift-format.sh diffs against SWIFT_FORMAT_BASE (PR base ref or HEAD^) and runs swift format lint --strict only on changed .swift files, printing per-file violations. Ran it locally against 63b7724^ and it correctly scoped to the one changed Swift file (Fixtures.swift) for that commit.
    - criterion: Packaging generates build artifacts without modifying tracked source files.
      result: pass
      notes: scripts/build-macos-app.sh stages the asset catalog into a build output directory rather than editing Sources/Lumo/Assets.xcassets in place; CI package job asserts git status --porcelain --untracked-files=all is empty after building.
    - criterion: RAW fixture storage/privacy/licensing is documented and the repository strategy is consistent with project guidance.
      result: pass
      notes: realworldtest ARW files (49MB each) were removed from git; realworldtest/README.md documents the LUMO_RAW_FIXTURE_DIR opt-in policy and the CC BY 4.0 license terms for locally supplied fixtures; .gitignore excludes realworldtest contents except the README.
    - criterion: CI verifies signed bundles and includes a minimal application-level smoke path for launch, open, settings/menu, and export flows.
      result: pass
      notes: package job runs scripts/verify-app-signature.sh; separate smoke job runs scripts/smoke-macos-app.sh, which drives Lumo via AppleScript/System Events through launch, File Open, Settings, and File Export, exiting 2 (treated as a non-failing skip) only when the hosted runner has no accessible WindowServer session.
    - criterion: Slow hardware/RAW coverage is separated or parallelized without reducing required regression coverage.
      result: pass
      notes: tests-fast and tests-slow lanes correctly split RAW/hardware-dependent classes from the deterministic lane. However tests-fast's skip list included EditPersistenceBenchmarkTests and TracingOverheadBenchmark, and tests-slow's filter omitted them, so neither lane ever selected those two classes. Both are opt-in, XCTSkipUnless-gated by env vars not set in CI, so effective CI behavior was already a no-op skip before and after this commit, not a functional regression, but the lane selection sets were inconsistent with the stated intent. Fixed in 502e211 by adding both classes to the slow-lane filter so every class skipped by the fast lane is explicitly selected by the slow lane.
  checks_run:
    - swift build
    - swift format lint --strict via scripts/check-swift-format.sh with SWIFT_FORMAT_BASE=63b7724^
    - grep -c func test across Tests/LumoKitTests/*.swift (735, matches README claim)
    - manual diff review of 63b7724 covering .github/workflows/ci.yml, .swift-format, scripts/check-swift-format.sh, scripts/smoke-macos-app.sh, realworldtest/README.md, .gitignore, docs/CODE_REVIEW.md, docs/PHASE2_SPEC.md, README.md
    - git status --porcelain to confirm only the intended ci.yml fix was introduced by this verification pass
  findings:
    - "tests-fast's skip list and tests-slow's filter were not complementary: EditPersistenceBenchmarkTests and TracingOverheadBenchmark were skipped by the fast lane but absent from the slow lane's filter, so neither lane selected them. Both are opt-in, XCTSkipUnless-gated by env vars CI never sets, so there was no observed behavior change, but the lane-selection sets did not match the stated intent. Fixed in 502e211."
  fixes:
    - Added EditPersistenceBenchmarkTests and TracingOverheadBenchmark to the tests-slow filter regex in .github/workflows/ci.yml (commit 502e211) so the fast and slow lane selections are complementary.
  verification_commits:
    - "502e211"
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T04:09:07.747Z
  session: 01MTMFIC1TH9QE2ZDU
---

## Objective

Restore reliable repository, formatting, documentation, and CI quality guardrails.

## Context

The README and living review documents contain stale test counts and historical architecture names. There is no repository Swift-format configuration, packaging can mutate tracked icon assets, large RAW fixtures are committed without LFS despite guidance saying otherwise, and CI lacks signature checks, UI smoke coverage, and useful fast/slow test separation.

## Acceptance criteria

- [ ] README and living audit/spec documents match the current product name, architecture, and test counts.
- [ ] A checked-in Swift-format configuration matches the house style and CI reports actionable changed-file violations.
- [ ] Packaging generates build artifacts without modifying tracked source files.
- [ ] RAW fixture storage/privacy/licensing is documented and the repository strategy is consistent with project guidance.
- [ ] CI verifies signed bundles and includes a minimal application-level smoke path for launch, open, settings/menu, and export flows.
- [ ] Slow hardware/RAW coverage is separated or parallelized without reducing required regression coverage.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-04T04:03:15.276Z

Implemented in 63b7724. Added checked-in Swift-format policy with strict changed-file linting, reconciled README/living docs to Lumo and the current 735-method inventory, and split CI into deterministic tests, slow RAW/hardware coverage, signed package verification, and an application smoke path. Packaging remains disposable/source-clean. Removed the committed 47 MB RAW blobs and documented the external, license/privacy-controlled LUMO_RAW_FIXTURE_DIR policy; capture scripts use the same policy. Verified: 725-test fast lane passed; 129-test slow selector passed with expected fixture skips; release bundle, icon, and strict signature checks passed; CI YAML and shell syntax passed. Local UI smoke was skipped because this session cannot activate macOS UI automation.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T04:09:07.754Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] README and living audit/spec documents match the current product name, architecture, and test counts. (pass) — README states 735 XCTest methods; grep of Tests/LumoKitTests/*.swift confirms 735 occurrences of func test. docs/CODE_REVIEW.md and docs/PHASE2_SPEC.md renamed LUTzy to Lumo and reconciled historical findings against the current architecture.
- [x] A checked-in Swift-format configuration matches the house style and CI reports actionable changed-file violations. (pass) — .swift-format is checked in; scripts/check-swift-format.sh diffs against SWIFT_FORMAT_BASE (PR base ref or HEAD^) and runs swift format lint --strict only on changed .swift files, printing per-file violations. Ran it locally against 63b7724^ and it correctly scoped to the one changed Swift file (Fixtures.swift) for that commit.
- [x] Packaging generates build artifacts without modifying tracked source files. (pass) — scripts/build-macos-app.sh stages the asset catalog into a build output directory rather than editing Sources/Lumo/Assets.xcassets in place; CI package job asserts git status --porcelain --untracked-files=all is empty after building.
- [x] RAW fixture storage/privacy/licensing is documented and the repository strategy is consistent with project guidance. (pass) — realworldtest ARW files (49MB each) were removed from git; realworldtest/README.md documents the LUMO_RAW_FIXTURE_DIR opt-in policy and the CC BY 4.0 license terms for locally supplied fixtures; .gitignore excludes realworldtest contents except the README.
- [x] CI verifies signed bundles and includes a minimal application-level smoke path for launch, open, settings/menu, and export flows. (pass) — package job runs scripts/verify-app-signature.sh; separate smoke job runs scripts/smoke-macos-app.sh, which drives Lumo via AppleScript/System Events through launch, File Open, Settings, and File Export, exiting 2 (treated as a non-failing skip) only when the hosted runner has no accessible WindowServer session.
- [x] Slow hardware/RAW coverage is separated or parallelized without reducing required regression coverage. (pass) — tests-fast and tests-slow lanes correctly split RAW/hardware-dependent classes from the deterministic lane. However tests-fast's skip list included EditPersistenceBenchmarkTests and TracingOverheadBenchmark, and tests-slow's filter omitted them, so neither lane ever selected those two classes. Both are opt-in, XCTSkipUnless-gated by env vars not set in CI, so effective CI behavior was already a no-op skip before and after this commit, not a functional regression, but the lane selection sets were inconsistent with the stated intent. Fixed in 502e211 by adding both classes to the slow-lane filter so every class skipped by the fast lane is explicitly selected by the slow lane.
Checks run:
- swift build
- swift format lint --strict via scripts/check-swift-format.sh with SWIFT_FORMAT_BASE=63b7724^
- grep -c func test across Tests/LumoKitTests/*.swift (735, matches README claim)
- manual diff review of 63b7724 covering .github/workflows/ci.yml, .swift-format, scripts/check-swift-format.sh, scripts/smoke-macos-app.sh, realworldtest/README.md, .gitignore, docs/CODE_REVIEW.md, docs/PHASE2_SPEC.md, README.md
- git status --porcelain to confirm only the intended ci.yml fix was introduced by this verification pass
Findings:
- tests-fast's skip list and tests-slow's filter were not complementary: EditPersistenceBenchmarkTests and TracingOverheadBenchmark were skipped by the fast lane but absent from the slow lane's filter, so neither lane selected them. Both are opt-in, XCTSkipUnless-gated by env vars CI never sets, so there was no observed behavior change, but the lane-selection sets did not match the stated intent. Fixed in 502e211.
Fixes:
- Added EditPersistenceBenchmarkTests and TracingOverheadBenchmark to the tests-slow filter regex in .github/workflows/ci.yml (commit 502e211) so the fast and slow lane selections are complementary.
Verification commits:
- 502e211
Actor: claude
Resolved model: sonnet
Pickup session: 01MTMFIC1TH9QE2ZDU
Summary: Verified LUMO-169: guardrails match acceptance criteria (README/docs reconciled at 735 tests, checked-in .swift-format with changed-file CI linting, disposable packaging, documented external RAW fixture policy, signed-bundle + smoke CI jobs). Found and fixed one CI lane-selection gap: EditPersistenceBenchmarkTests and TracingOverheadBenchmark were skipped from tests-fast but absent from tests-slow's filter. Added them to the slow-lane filter in 502e211.
