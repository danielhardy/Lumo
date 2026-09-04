---
id: LUMO-163
title: "Audit: sign packaged app and apply entitlements"
type: bug
status: done
priority: urgent
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - security
  - release
  - packaging
  - audit
created: 2026-09-03T23:28:32.167Z
updated: 2026-09-04T01:46:48.327Z
order: a0
board: product
commits:
  - 29d2798
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The packaged .app passes codesign --verify --deep --strict after all resources are present
      result: pass
      notes: build-macos-app.sh assembles MacOS binary, compiled asset catalog, Info.plist, and optional embedded provisioning profile before signing; verify-app-signature.sh re-runs the strict verify independently.
    - criterion: The app sandbox and declared file/bookmark entitlements are applied to the signed app
      result: pass
      notes: codesign --entitlements Sources/Lumo/Lumo.entitlements embeds app-sandbox, user-selected read-write, removable-media read-only, and bookmarks.app-scope; verify-app-signature.sh decodes the embedded entitlements and asserts all four values.
    - criterion: Release signing uses the intended identity/profile when configured, with a documented local/CI fallback
      result: pass
      notes: LUMO_CODESIGN_IDENTITY/CODE_SIGN_IDENTITY and LUMO_PROVISIONING_PROFILE/PROVISIONING_PROFILE are honored when set, falling back to ad-hoc (-) signing; documented in README under Preparing for the App Store.
    - criterion: CI inspects signature validity and asserts the expected entitlement keys and values
      result: pass
      notes: ci.yml runs scripts/verify-app-signature.sh after packaging, which fails the job on any signature or entitlement mismatch.
    - criterion: Packaging does not mutate tracked source assets while producing the app
      result: pass
      notes: Assets.xcassets is copied into .build/lumo-icon-asset-validation before actool/sips touch it; ci.yml additionally asserts git diff --exit-code on Sources/Lumo/Assets.xcassets.
  checks_run:
    - swift build -c release
    - swift test (715 passed, 14 expected skips)
    - scripts/build-macos-app.sh
    - scripts/verify-app-signature.sh
    - scripts/verify-app-icon.sh
    - git diff --exit-code -- Sources/Lumo/Assets.xcassets
    - git diff --check
    - dg validate
  findings: []
  fixes: []
  verification_commits:
    - 29d2798
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T01:46:48.323Z
  session: 01MTMAHXXX8JOLKVG8
---

## Objective

Make the macOS application bundle produced by the release packaging path validly signed and enforce the declared sandbox entitlements.

## Context

`Package.swift` excludes `Sources/Lumo/Lumo.entitlements`, while `scripts/build-macos-app.sh` assembles the `.app` bundle after linking and never signs the completed bundle. The current bundle fails strict `codesign` verification and has no applied entitlements. CI validates icons and bundle contents but not signature validity or entitlement values.

## Acceptance criteria

- [ ] The packaged `.app` passes `codesign --verify --deep --strict` after all resources are present.
- [ ] The app sandbox and declared file/bookmark entitlements are applied to the signed app.
- [ ] Release signing uses the intended identity/profile when configured, with a documented local/CI fallback.
- [ ] CI inspects signature validity and asserts the expected entitlement keys and values.
- [ ] Packaging does not mutate tracked source assets while producing the app.

## Implementation notes

Likely touch points: `Package.swift`, `scripts/build-macos-app.sh`, `.github/workflows/ci.yml`, and `Sources/Lumo/Lumo.entitlements`. Assemble first, sign the final bundle, and verify the exact artifact that would be distributed.

### Comment — codex @ 2026-09-04T01:23:14.258Z

Implemented in 29d2798. Packaging stages the full asset catalog under .build, assembles all resources before signing, uses LUMO_CODESIGN_IDENTITY/CODE_SIGN_IDENTITY and optional LUMO_PROVISIONING_PROFILE/PROVISIONING_PROFILE with ad-hoc fallback, and verifies codesign --verify --deep --strict plus all four expected entitlement values. CI runs the signature verifier and asserts tracked asset sources remain unchanged. Checks: swift test (715 passed, 14 expected skips), swift build -c release, bundle/icon/signature verification, git diff --check, dg validate.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T01:46:48.325Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The packaged .app passes codesign --verify --deep --strict after all resources are present (pass) — build-macos-app.sh assembles MacOS binary, compiled asset catalog, Info.plist, and optional embedded provisioning profile before signing; verify-app-signature.sh re-runs the strict verify independently.
- [x] The app sandbox and declared file/bookmark entitlements are applied to the signed app (pass) — codesign --entitlements Sources/Lumo/Lumo.entitlements embeds app-sandbox, user-selected read-write, removable-media read-only, and bookmarks.app-scope; verify-app-signature.sh decodes the embedded entitlements and asserts all four values.
- [x] Release signing uses the intended identity/profile when configured, with a documented local/CI fallback (pass) — LUMO_CODESIGN_IDENTITY/CODE_SIGN_IDENTITY and LUMO_PROVISIONING_PROFILE/PROVISIONING_PROFILE are honored when set, falling back to ad-hoc (-) signing; documented in README under Preparing for the App Store.
- [x] CI inspects signature validity and asserts the expected entitlement keys and values (pass) — ci.yml runs scripts/verify-app-signature.sh after packaging, which fails the job on any signature or entitlement mismatch.
- [x] Packaging does not mutate tracked source assets while producing the app (pass) — Assets.xcassets is copied into .build/lumo-icon-asset-validation before actool/sips touch it; ci.yml additionally asserts git diff --exit-code on Sources/Lumo/Assets.xcassets.
Checks run:
- swift build -c release
- swift test (715 passed, 14 expected skips)
- scripts/build-macos-app.sh
- scripts/verify-app-signature.sh
- scripts/verify-app-icon.sh
- git diff --exit-code -- Sources/Lumo/Assets.xcassets
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- 29d2798
Actor: claude
Resolved model: sonnet
Pickup session: 01MTMAHXXX8JOLKVG8
Summary: Verified: packaging stages the asset catalog under .build (no tracked-asset mutation), signs the assembled bundle with the entitlements file, and passes strict codesign verification with all 4 expected entitlement values. CI wires verify-app-signature.sh plus a git diff guard on Assets.xcassets. Re-ran locally: swift build -c release, swift test (715 passed, 14 expected skips), scripts/build-macos-app.sh, scripts/verify-app-signature.sh, scripts/verify-app-icon.sh, git diff --exit-code on Assets.xcassets, git diff --check, dg validate — all pass. No blockers; no fixes needed.
