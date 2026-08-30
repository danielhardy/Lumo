---
id: LUMO-002
title: Rename the LUTzy fork to Lumo across package and app surfaces
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:identity
  - phase:0
created: 2026-08-30T18:30:17.648Z
updated: 2026-08-30T18:30:33.818Z
estimate: 5
order: 1fu8n1fu
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
