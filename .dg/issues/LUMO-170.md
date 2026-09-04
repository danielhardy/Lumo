---
id: LUMO-170
title: "Audit: bound Photos import memory and avoid repeated hashing"
type: task
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - performance
  - memory
  - photos-import
  - audit
created: 2026-09-03T23:30:00.844Z
updated: 2026-09-04T02:31:09.084Z
order: zh
board: product
commits:
  - a10ddac
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Photos transfer memory remains bounded during selection import.
      result: pass
      notes: The picker path transfers and publishes one item at a time; no temporary batch payload array is retained, picker selection remains capped at 50, and thumbnail work uses the existing four-worker/24-queued scheduler. Accepted originals are retained once because RAW re-development requires full bytes.
    - criterion: Large payload hashing does not repeat across import consumers or block the UI actor.
      result: pass
      notes: ContentView computes one SHA-256 digest in a utility Task after transfer. PhotoImportItem carries it through the durable identity fallback and PhotoSourceFingerprint; collection item fingerprints are reused by thumbnails, first render, navigation, and adjacent prefetch.
    - criterion: Import correctness and durable identity are preserved.
      result: pass
      notes: Photos local identifiers remain the preferred identity; identifier-free imports preserve content-plus-name-plus-ordinal identity, source bytes, orientation, and existing RAW/content classification behavior.
    - criterion: Regression coverage and documentation cover the new invariant.
      result: pass
      notes: Added digest propagation and precomputed ImageSource fingerprint tests and documented the memory/hash invariant in docs/PHOTOS_IMPORT_PERFORMANCE.md.
  checks_run:
    - swift test --filter PhotosImportTests|PhotoAssetTests|ImageSourceTests|ThumbnailTests (39 passed)
    - swift test (727 passed, 14 expected skips)
    - swift build -c release (passed)
    - git diff --check (passed)
    - dg validate (passed; pre-existing unknown pickup-runner model warning)
  findings: []
  fixes: []
  verification_commits:
    - a10ddac
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T02:31:09.078Z
  session: 01MTMBUKJNM5NQLBDU
---

## Objective

Audit: bound Photos import memory and avoid repeated hashing

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T02:31:09.082Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Photos transfer memory remains bounded during selection import. (pass) — The picker path transfers and publishes one item at a time; no temporary batch payload array is retained, picker selection remains capped at 50, and thumbnail work uses the existing four-worker/24-queued scheduler. Accepted originals are retained once because RAW re-development requires full bytes.
- [x] Large payload hashing does not repeat across import consumers or block the UI actor. (pass) — ContentView computes one SHA-256 digest in a utility Task after transfer. PhotoImportItem carries it through the durable identity fallback and PhotoSourceFingerprint; collection item fingerprints are reused by thumbnails, first render, navigation, and adjacent prefetch.
- [x] Import correctness and durable identity are preserved. (pass) — Photos local identifiers remain the preferred identity; identifier-free imports preserve content-plus-name-plus-ordinal identity, source bytes, orientation, and existing RAW/content classification behavior.
- [x] Regression coverage and documentation cover the new invariant. (pass) — Added digest propagation and precomputed ImageSource fingerprint tests and documented the memory/hash invariant in docs/PHOTOS_IMPORT_PERFORMANCE.md.
Checks run:
- swift test --filter PhotosImportTests|PhotoAssetTests|ImageSourceTests|ThumbnailTests (39 passed)
- swift test (727 passed, 14 expected skips)
- swift build -c release (passed)
- git diff --check (passed)
- dg validate (passed; pre-existing unknown pickup-runner model warning)
Findings:
- None
Fixes:
- None
Verification commits:
- a10ddac
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTMBUKJNM5NQLBDU
Summary: Photos imports now keep one in-flight payload, hash each payload once off the main actor, and reuse that digest through identity, source, thumbnail, and render paths. Full-fidelity originals and existing bounded thumbnail scheduling are preserved.
