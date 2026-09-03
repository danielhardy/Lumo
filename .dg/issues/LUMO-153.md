---
id: LUMO-153
title: Removable-volume list shows non-photo/unreadable volumes indefinitely
type: task
status: done
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-03T03:14:15.176Z
updated: 2026-09-03T05:26:58.516Z
order: zzzq
board: product
commits:
  - 1a8941b
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Decide whether unreadable removable volumes should be filtered, labeled distinctly, or left as-is with rationale recorded
      result: pass
    - criterion: If filtered/labeled, implement and cover with a test using an injected MediaVolumeProviding fixture
      result: pass
  checks_run:
    - swift test --filter MediaVolume — 7 passed
    - swift test — 693 executed, 14 skipped, 0 failures
    - swift build -c release — clean, with pre-existing Core Image deprecation warnings
    - git diff --check — clean
    - dg validate — OK; pre-existing pickup-model and low-context warnings only
  findings:
    - Unreadable volumes are labeled Access needed — open to check for photos rather than filtered, because filtering could hide a camera card whose contents require a user grant and a DCIM probe is not reliable under sandbox restrictions.
  fixes: []
  verification_commits:
    - 1a8941b
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-03T05:26:58.513Z
  session: 01MTL2V49RBGD8J6Q7
---

Parent: LUMO-152 (verification finding, non-blocking)

## Context

LUMO-152 (d57a92d) changed `MountedMediaVolumeProvider.discoverMountedVolumes` in
`Sources/LumoKit/Models/MediaVolume.swift` so that a removable/ejectable volume the sandbox
cannot yet read is kept in the discovery list (so `scan()` can later recover access through the
Open panel), instead of being filtered out. Before this change, a volume was only listed if it
was both readable and `containsSupportedFile(in:)` returned true.

The tradeoff: any unreadable removable/ejectable volume is now shown regardless of whether it
actually has any images on it — e.g. a blank/reformatted SD card, an OS install USB stick, or a
Time Machine backup volume that happens to be removable. The user has no way to tell "no photos"
from "no permission yet" until they open it and go through the Open-panel recovery flow, which is
more friction than before for volumes that were never going to have anything importable.

## Suggested direction

Consider a lighter-weight signal to distinguish "plausibly a camera/media card" from "definitely
not," e.g. checking for a DCIM directory or a known camera filesystem layout without requiring a
full readable scan, before deciding whether an unreadable volume is worth listing. Not required —
UX polish only.

## Acceptance criteria

- [ ] Decide whether unreadable removable volumes should be filtered, labeled distinctly (e.g.
      "tap to check for photos"), or left as-is with rationale recorded.
- [ ] If filtered/labeled, implement and cover with a test using an injected
      `MediaVolumeProviding` fixture.

## Agent log

- 2026-09-03T05:26:58.514Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Decide whether unreadable removable volumes should be filtered, labeled distinctly, or left as-is with rationale recorded (pass)
- [x] If filtered/labeled, implement and cover with a test using an injected MediaVolumeProviding fixture (pass)
Checks run:
- swift test --filter MediaVolume — 7 passed
- swift test — 693 executed, 14 skipped, 0 failures
- swift build -c release — clean, with pre-existing Core Image deprecation warnings
- git diff --check — clean
- dg validate — OK; pre-existing pickup-model and low-context warnings only
Findings:
- Unreadable volumes are labeled Access needed — open to check for photos rather than filtered, because filtering could hide a camera card whose contents require a user grant and a DCIM probe is not reliable under sandbox restrictions.
Fixes:
- None
Verification commits:
- 1a8941b
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTL2V49RBGD8J6Q7
Summary: Chose distinct labeling for unreadable removable volumes. Discovery now records when sandbox access is still required; the Import menu and selector identify those volumes as Access needed and tell the user to open them to check for photos. Readable volumes retain supported-image filtering, preserving the permission-recovery path without hiding camera cards. Added injected-provider coverage.
