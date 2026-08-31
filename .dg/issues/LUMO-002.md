---
id: LUMO-002
title: Rename the LUTzy fork to Lumo across package and app surfaces
type: task
status: verification
priority: urgent
labels:
  - mvp
  - epic:identity
  - phase:0
created: 2026-08-30T18:30:17.648Z
updated: 2026-08-30T19:15:16.712Z
depends_on:
  - LUMO-060
estimate: 5
order: a0
board: product
---

## Objective

Apply one explicit rename map across targets, modules, source/test directories, entry point, entitlements, assets, schemes, bundle-facing identifiers, and user-visible strings.

## Context

Part of **Epic 0 — Product identity and clean baseline**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- Inventory rename sites with targeted search before moving anything.
- Rename Package.swift products/targets and Swift imports together with filesystem paths.
- Update executable entry point, entitlements references, test target/module names, and user-visible product strings.

## Acceptance criteria

- [ ] No application-facing or package-facing LUTzy identifier remains outside attribution/history documents.
- [ ] The executable and library are named Lumo and LumoKit, and tests import LumoKit.
- [ ] A clean build reaches compilation after all moves with no compatibility shim targets.

## Verification

- Run targeted identifier searches with documented allowlisted attribution hits.
- Run swift build and swift test.

## Out of scope

- New editing features.
- Removal of LUT derivation or other inherited capabilities.

### Comment — codex @ 2026-08-30T18:41:58.434Z

Implemented and committed as c1feab7. Renamed package/products/targets and moved Sources/LUTzy→Sources/Lumo, Sources/LUTzyKit→Sources/LumoKit, Tests/LUTzyKitTests→Tests/LumoKitTests; updated entry point, entitlements, imports, test paths, notifications, persisted key, scripts, CI, README, and active guidance. Targeted search leaves LUTzy only in preserved fork/source-history docs. Verification: swift build passed; swift test passed (308 executed, 20 skipped, 0 failures).

### Comment — claude @ 2026-08-30T19:12:18.896Z

## Verification report — PASS

**Scope checked:** correctness, maintainability, security, performance; independent re-run of
declared checks.

**Build/test:** `swift build` clean; `swift test` — 308 executed, 20 skipped, 0 failures
(matches implementer's report).

**Identifier sweep:** grep for `LUTzy` (case-insensitive) across the tree, excluding `.git`/`.dg`/`.build`.
Remaining hits are confined to:
- `.context/initial_concept.md` — the source product brief, describes the pre-rename starting point (historical).
- `docs/superpowers/plans/2026-08-06-*.md` — dated planning transcripts for already-completed steps (historical).
- `docs/PHASE2_SPEC.md`, `docs/CODE_REVIEW.md` — living reference docs per CLAUDE.md, not attribution/history. Filed as **LUMO-060** (backlog, `verification` label, non-blocking) rather than fixed inline, since it's doc-only cleanup outside this issue's declared scope (Package.swift/imports/paths/entry point/entitlements/test target/user-visible strings).
- `LICENSE` — unchanged; copyright is "Tim", never referenced LUTzy by name. No fork-acknowledgment text exists in README before or after the rename — pre-existing gap, not introduced by this change.

**Bundle-facing surfaces:** Package.swift products/targets (`Lumo`, `LumoKit`), entry point
(`Sources/Lumo/LumoApp.swift`, `@main struct LumoApp`), entitlements (`Lumo.entitlements`,
contents unaffected), `Notification.Name` constants (`Lumo.openImage` etc.), `PackageSettingsTests`
(asserts all three targets by name — passing) all consistent. One persisted `UserDefaults` key
renamed (`lutzy.collapsedLUTCategories` → `lumo.collapsedLUTCategories`); harmless pre-ship.

**No compatibility shims** introduced (no re-exports, no `LUTzy` typealiases).

**Verdict:** acceptance criteria met. No blocking issues. One non-blocking child ticket filed
(LUMO-060) for stale paths in two living docs.

### Comment — claude @ 2026-08-30T19:15:16.712Z

Automatic merge into `main` failed: Issue has no branch to merge

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
