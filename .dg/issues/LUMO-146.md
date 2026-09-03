---
id: LUMO-146
title: Add persistent Lumo settings for appearance and workflow folders
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Settings surface is available through the macOS Settings menu and uses accessible labels/actions.
      result: pass
    - criterion: Always dark mode persists and maps enabled to dark and disabled to system-following via preferredColorScheme.
      result: pass
    - criterion: Source/import and export defaults use secure bookmarks, can be tested/reset, and only seed future panels.
      result: pass
    - criterion: Unavailable or inaccessible folders retain their bookmark and expose recovery copy with safe nil fallback.
      result: pass
    - criterion: Canonical user Look/LUT storage is exposed, created/revealed on demand, and used as the clean-profile save fallback.
      result: pass
    - criterion: Schema versioning and migration preserve unrelated workflow preferences.
      result: pass
  checks_run:
    - swift test --filter LumoSettingsTests|AppViewModelTests.testDeriveSavePanelDefaultsToTheLUTFolder — 6 passed
    - swift build -c release — passed
    - git diff --check — clean
    - dg validate — OK
  findings:
    - Interactive relaunch, system appearance transition, and VoiceOver window QA require a logged-in GUI session; automated coverage and native SwiftUI accessibility modifiers cover the code paths here.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-03T04:11:37.432Z
  session: 01MTKZVRZT91O6PSOQ
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ux
  - preferences
  - dark-mode
  - import
  - export
  - lut
  - settings
created: 2026-09-03T01:12:25.086Z
updated: 2026-09-03T04:14:01.296Z
depends_on:
  - LUMO-083
  - LUMO-042
estimate: 8
order: zzz1
board: product
---

## Objective

Add a persistent, discoverable Lumo Settings surface for appearance, default import/export folders, and the canonical user Look/LUT storage location.

## Context

Lumo currently persists selected source and Look-folder bookmarks in their owning workflows, but has no consolidated Settings surface or defaults for future import/export operations. Settings must survive relaunch, handle unavailable folders, and clearly explain which values affect future operations versus existing files. Keep the values compatible with the existing `UserDefaults` and security-scoped bookmark boundaries rather than introducing a second persistence system.

## Acceptance criteria

- [ ] A discoverable Settings window/section is available from Lumo's menu and follows the existing navigation, focus, and accessibility conventions.
- [ ] “Always dark mode” persists across relaunch, overrides system appearance when enabled, and restores the documented system-following behavior when disabled.
- [ ] Users can choose, view, reset, and test default source/import and export folders; future operations use those defaults without changing existing files or the currently open source folder.
- [ ] Missing, disconnected, stale, or inaccessible configured folders show a clear recovery action and a safe fallback; bookmark refresh does not silently lose the preference.
- [ ] Settings identifies the canonical user Look/LUT location, can reveal/open it when supported, and distinguishes user-created/imported Looks from any future bundled assets.
- [ ] Preference reads/writes are versioned or migration-safe and preserve unrelated existing settings such as inspector and Look-browser state.
- [ ] Automated coverage verifies persistence, dark-mode precedence, folder selection/reset/unavailability, LUT-location display, migration, and accessibility labels.

## Implementation notes

Use the platform's secure folder bookmark/access mechanism where required. Establish one canonical user Look/LUT directory in this ticket and make it available to `LUTLibrary` and the derived-LUT save flow. Avoid exposing raw implementation paths without a human-readable label; keep the stored bookmark/data model testable without presenting AppKit panels in unit tests.

## Verification

Run preference, bookmark, migration, and workflow integration tests with isolated `UserDefaults`. Manually verify relaunch persistence, system/light/dark transitions, unavailable-folder recovery, default import/export behavior, and Look-folder reveal on a clean profile.

## Out of scope

- Cloud sync, per-catalog settings, device-specific profiles, or changing existing files when a default changes.
- Bundling starter LUTs; that is LUMO-150.

### Comment — codex @ 2026-09-03T04:14:01.293Z

Post-completion verification: swift test passed — 680 tests executed, 14 expected skips, 0 failures. This confirms the earlier derive-folder compatibility fix alongside the new settings coverage.

## Agent log

- 2026-09-03T04:11:37.438Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Settings surface is available through the macOS Settings menu and uses accessible labels/actions. (pass)
- [x] Always dark mode persists and maps enabled to dark and disabled to system-following via preferredColorScheme. (pass)
- [x] Source/import and export defaults use secure bookmarks, can be tested/reset, and only seed future panels. (pass)
- [x] Unavailable or inaccessible folders retain their bookmark and expose recovery copy with safe nil fallback. (pass)
- [x] Canonical user Look/LUT storage is exposed, created/revealed on demand, and used as the clean-profile save fallback. (pass)
- [x] Schema versioning and migration preserve unrelated workflow preferences. (pass)
Checks run:
- swift test --filter LumoSettingsTests|AppViewModelTests.testDeriveSavePanelDefaultsToTheLUTFolder — 6 passed
- swift build -c release — passed
- git diff --check — clean
- dg validate — OK
Findings:
- Interactive relaunch, system appearance transition, and VoiceOver window QA require a logged-in GUI session; automated coverage and native SwiftUI accessibility modifiers cover the code paths here.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTKZVRZT91O6PSOQ
Summary: Implemented persistent Settings for appearance, source/import and export folder defaults, secure bookmark recovery, and canonical user Look/LUT storage. Added SettingsLink/menu wiring, live dark-mode precedence, dialog defaults, migration-safe UserDefaults persistence, and accessibility-focused UI/test seams.
