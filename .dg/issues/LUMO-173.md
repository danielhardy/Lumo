---
id: LUMO-173
title: "Audit: move folder scan I/O off main actor and remove quadratic work"
type: task
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - performance
  - library
  - scanning
  - audit
created: 2026-09-03T23:31:00.000Z
updated: 2026-09-04T09:01:05.308Z
order: t
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: File resource queries and fingerprints are computed once off-main before publication.
      result: pass
      notes: The detached discovery producer captures one PhotoSourceFingerprint per canonical file and constructs the sendable PhotoAsset before yielding it; PhotoAssetSource reuses the supplied fingerprint when deriving the ID, eliminating the prior second fingerprint read on publication.
    - criterion: Duplicate detection uses a set or equivalent indexed structure.
      result: pass
      notes: Folder publication tracks discovered PhotoAssetID values in Set<PhotoAssetID>, replacing the accumulated-array contains scan.
    - criterion: Batch ordering avoids repeated full-array sorting while preserving deterministic library order.
      result: pass
      notes: Discovery records are sorted once off-main with the existing subfolder/natural-name/path comparator, then emitted as ordered batches; publication no longer sorts the accumulated items per batch.
    - criterion: Cancellation and stale-scan generation behavior remain intact.
      result: pass
      notes: The existing scanGeneration and Task cancellation guards remain on every event and before completion; focused folder tests including switching folders passed.
    - criterion: Benchmarks or instrumentation cover realistic 1k/10k item folders.
      result: pass
      notes: "Added opt-in LibraryScanPerformanceTests, which creates valid nested 1,000- and 10,000-item JPEG folders, verifies deterministic order, and reports first-row/discovery timings. Local run: 1k first row 241.6 ms/discovery 1.1 s; 10k first row 2.4 s/discovery 78.2 s."
  checks_run:
    - swift test --filter 'LibraryScanTests|PhotoAssetTests' (28 passed, 0 failed)
    - LUMO_SCAN_BENCHMARK=1 swift test --filter LibraryScanPerformanceTests (1 passed; 1k/10k profile emitted)
    - swift test (741 passed, 34 expected skips, 0 failures)
    - swift build -c release
    - git diff --check
    - dg validate (OK; pre-existing pickup-model and LUMO-175 context warnings only)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-04T09:01:05.301Z
---

## Objective

Keep folder discovery responsive by moving file identity work off the main actor and making batch merge work subquadratic.

## Context

Although discovery is streamed, batch publication constructs file-backed assets on `@MainActor`. Identity/fingerprint work performs file reads, while each item scans the accumulated array for duplicates and triggers a full sort after each batch. Large, removable, or network-backed folders can visibly block the UI.

## Acceptance criteria

- [ ] File resource queries and fingerprints are computed once off-main before publication.
- [ ] Duplicate detection uses a set or equivalent indexed structure.
- [ ] Batch ordering avoids repeated full-array sorting while preserving deterministic library order.
- [ ] Cancellation and stale-scan generation behavior remain intact.
- [ ] Benchmarks or instrumentation cover realistic 1k/10k item folders.

## Agent log

- 2026-09-04T09:01:05.306Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] File resource queries and fingerprints are computed once off-main before publication. (pass) — The detached discovery producer captures one PhotoSourceFingerprint per canonical file and constructs the sendable PhotoAsset before yielding it; PhotoAssetSource reuses the supplied fingerprint when deriving the ID, eliminating the prior second fingerprint read on publication.
- [x] Duplicate detection uses a set or equivalent indexed structure. (pass) — Folder publication tracks discovered PhotoAssetID values in Set<PhotoAssetID>, replacing the accumulated-array contains scan.
- [x] Batch ordering avoids repeated full-array sorting while preserving deterministic library order. (pass) — Discovery records are sorted once off-main with the existing subfolder/natural-name/path comparator, then emitted as ordered batches; publication no longer sorts the accumulated items per batch.
- [x] Cancellation and stale-scan generation behavior remain intact. (pass) — The existing scanGeneration and Task cancellation guards remain on every event and before completion; focused folder tests including switching folders passed.
- [x] Benchmarks or instrumentation cover realistic 1k/10k item folders. (pass) — Added opt-in LibraryScanPerformanceTests, which creates valid nested 1,000- and 10,000-item JPEG folders, verifies deterministic order, and reports first-row/discovery timings. Local run: 1k first row 241.6 ms/discovery 1.1 s; 10k first row 2.4 s/discovery 78.2 s.
Checks run:
- swift test --filter 'LibraryScanTests|PhotoAssetTests' (28 passed, 0 failed)
- LUMO_SCAN_BENCHMARK=1 swift test --filter LibraryScanPerformanceTests (1 passed; 1k/10k profile emitted)
- swift test (741 passed, 34 expected skips, 0 failures)
- swift build -c release
- git diff --check
- dg validate (OK; pre-existing pickup-model and LUMO-175 context warnings only)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: unknown
Summary: Moved folder identity/fingerprint work into detached discovery, indexed duplicate checks, and one-time deterministic batch ordering; added 1k/10k scan instrumentation.
