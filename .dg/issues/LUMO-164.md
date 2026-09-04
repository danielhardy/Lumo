---
id: LUMO-164
title: "Audit: make export location metadata privacy explicit"
type: bug
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - security
  - privacy
  - export
  - audit
created: 2026-09-03T23:28:45.962Z
updated: 2026-09-04T01:54:09.350Z
order: a0
board: product
commits:
  - 9b84776
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The export surface exposes clear independent camera-metadata and location controls
      result: pass
      notes: Both single-save and batch-folder panels show Preserve camera metadata (EXIF/TIFF) and Include location metadata (GPS); GPS is disabled when camera metadata is off.
    - criterion: The default behavior is documented and deliberate
      result: pass
      notes: ExportOptions preserves camera metadata but defaults location to exclude; README documents this privacy choice and legacy option decoding remains location-excluded.
    - criterion: JPEG, TIFF, and PNG honor location policy for URL and Data sources
      result: pass
      notes: RenderEngine conditionally copies the GPS dictionary from either ImageSource backing for all three formats.
    - criterion: Regression tests verify GPS stripping and explicit preservation
      result: pass
      notes: RenderEngineTests cover URL/Data x JPEG/TIFF/PNG exclusion and explicit inclusion, plus existing full metadata and strip tests.
    - criterion: The choice is visible before Photos delivery and file export
      result: pass
      notes: The shared export accessory is attached to both save and batch folder panels; Photos receives the already-encoded bytes.
  checks_run:
    - swift test (717 passed, 14 expected skips)
    - swift build -c release
    - git diff --check
    - dg validate
  findings: []
  fixes: []
  verification_commits:
    - 9b84776
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T01:54:09.347Z
  session: 01MTMAMP4VBR8DIKMC
---

## Objective

Make export handling of GPS/location metadata explicit and safe for users sharing images.

## Context

`ExportOptions` defaults to metadata preservation, and the renderer copies EXIF/TIFF/GPS dictionaries. The export UI currently exposes no metadata or location control, so a photo can silently retain precise location data when exported or delivered to Photos.

## Acceptance criteria

- [ ] The export surface exposes a clear control for preserving camera metadata and separately for including location metadata.
- [ ] The default behavior is documented and reflects a deliberate privacy choice.
- [ ] JPEG, TIFF, and PNG exports honor the chosen location policy for both URL- and Data-backed sources.
- [ ] Regression tests verify GPS is stripped when requested and preserved only when explicitly allowed.
- [ ] The choice is visible before Photos delivery and file export, not only in a hidden advanced path.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-04T01:53:59.122Z

Implemented in 9b84776. ExportOptions now separates camera metadata from GPS location with location excluded by default and legacy decoding fail-safe; the save and batch export panels visibly expose both privacy choices, and RenderEngine applies the policy to JPEG, TIFF, and PNG for URL/Data sources. Verification: swift test (717 passed, 14 expected skips), swift build -c release, git diff --check, dg validate.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T01:54:09.348Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The export surface exposes clear independent camera-metadata and location controls (pass) — Both single-save and batch-folder panels show Preserve camera metadata (EXIF/TIFF) and Include location metadata (GPS); GPS is disabled when camera metadata is off.
- [x] The default behavior is documented and deliberate (pass) — ExportOptions preserves camera metadata but defaults location to exclude; README documents this privacy choice and legacy option decoding remains location-excluded.
- [x] JPEG, TIFF, and PNG honor location policy for URL and Data sources (pass) — RenderEngine conditionally copies the GPS dictionary from either ImageSource backing for all three formats.
- [x] Regression tests verify GPS stripping and explicit preservation (pass) — RenderEngineTests cover URL/Data x JPEG/TIFF/PNG exclusion and explicit inclusion, plus existing full metadata and strip tests.
- [x] The choice is visible before Photos delivery and file export (pass) — The shared export accessory is attached to both save and batch folder panels; Photos receives the already-encoded bytes.
Checks run:
- swift test (717 passed, 14 expected skips)
- swift build -c release
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- 9b84776
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTMAMP4VBR8DIKMC
Summary: Completed: export UI makes camera metadata and GPS location independent and visible; GPS defaults to excluded, is opt-in, and is enforced for URL/Data JPEG, TIFF, and PNG exports. Tests and release build pass.
