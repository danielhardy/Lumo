---
id: LUMO-163
title: "Audit: sign packaged app and apply entitlements"
type: bug
status: backlog
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
updated: 2026-09-03T23:28:32.167Z
order: zzy
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
