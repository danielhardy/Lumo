---
id: LUMO-120
title: Investigate RAW decoder drift causing 3 local-fixture-gated test failures
type: bug
status: done
priority: low
labels:
  - verification
created: 2026-09-02T01:29:36.608Z
updated: 2026-09-02T04:50:20.504Z
order: a0
board: product
commits:
  - 7d0cfd7
---

## Objective

Determine why 3 tests gated on a local, non-checked-in real RAW fixture (`Fixtures.localRAWURL`,
currently a Leica M11 DNG at `realworldtest/20260525_102528_L1031183.DNG`) now fail on this machine,
and either fix the underlying assumption or adjust the tests to tolerate the current decoder behavior.

## Context

Parent: LUMO-114 (performance telemetry work). Discovered incidentally while running the full
`swift test` suite during LUMO-114's counterpoint verification (2026-09-02, HEAD 90c1b95) — this is
a non-blocking, unrelated finding, not a regression from LUMO-114/115/116/117's changes (confirmed by
diffing LUMO-114's own commit 6416923 against `ImageSource.swift`: it only adds a `traceToken` computed
at init and does not touch `kind(forData:)` or `RAWCapabilities` probing).

Failing tests, reproducible and deterministic on this machine:
- `ImageSourceTests.testRAWBytesAreDetectedWithoutAFilename` — `ImageSource.kind(forData:)` now
  classifies the local RAW fixture's bytes as `.standard` instead of `.raw`.
- `PreviewCutoverTests.testRAWDevelopReachesThePreview` — times out waiting for the developed preview;
  the "reach CIRAWFilter through the preview path" delta assertion also fails (`0` vs expected `>= 2`).
- `RAWCapabilitiesTests.testProbingARealRAWReportsItsDecodersSeeds` — asserts the decoder enables lens
  correction by default; the probe now reports `lensCorrectionEnabled false (supported: false)` for
  this Leica M11 DNG.

All three point at the same root cause candidate: this machine's current ImageIO/CIRAWFilter RAW
decoder no longer recognizes this fixture the same way it did when these tests were written (UTI
sniffing, lens-correction support, and full RAW-develop-to-preview all changed together for the same
file). This is most likely OS/decoder version drift rather than a Lumo code defect, but needs
confirmation.

## Acceptance criteria

- [ ] Root-cause the behavior change (compare decoder/ImageIO version against when these tests last
      passed, or reproduce against a second RAW fixture if available).
- [ ] Either restore the expected behavior if it's a genuine regression in Lumo's RAW handling, or
      update the three tests/fixture expectations to match current, correct decoder behavior if it's
      environmental drift.
- [ ] `swift test` passes with no local-RAW-fixture-gated failures on a machine that has the fixture.

## Scope boundaries

Independent of LUMO-114's telemetry/observability work; do not block LUMO-114 on this.


### Comment — codex @ 2026-09-02T04:45:17.538Z

Implemented in commit 7d0cfd7. Root cause confirmed as decoder/fixture capability drift, not a Lumo RAW pipeline regression: macOS 26.6 / Xcode 26.6 reports DSC07241.ARW lens correction unsupported/false while DSC07826.ARW reports supported/true, and both pass RAW byte classification and preview development. Expanded local fixture discovery to probe every available RAW, made byte/preview checks skip only when the current decoder cannot support that optional path, and replaced Leica-specific seed snapshots with live CIRAWFilter comparisons including gated and unsupported values. Verification: focused RAW tests pass; swift build -c release passes; full swift test passes 594 tests with 13 expected skips and 0 failures; git diff --check and dg validate pass.


### Comment — claude @ 2026-09-02T04:50:17.360Z

## Counterpoint verification — PASS

Independent re-verification of commit 7d0cfd7 (implementation by codex).

**Checks run:**
- `swift build -c release` — clean build.
- `swift test --filter 'ImageSourceTests|PreviewCutoverTests|RAWCapabilitiesTests'` — all pass, including the three originally-failing tests.
- `swift test` (full suite) — 594 tests, 13 skipped, 0 failures. Matches the implementer's reported numbers exactly.
- `git diff --check` — clean (no whitespace errors).
- `dg validate` — OK.

**Code review of the fix (Fixtures.swift, ImageSourceTests.swift, PreviewCutoverTests.swift, RAWCapabilitiesTests.swift):**
- Root cause is credible and independently corroborated: this run's local `realworldtest/` now has two ARW fixtures (DSC07241.ARW, DSC07826.ARW), and the live run shows exactly the asymmetry described — DSC07241 reports `lensCorrectionEnabled false (supported: false)`, DSC07826 reports `true (supported: true)`. That's real decoder/file variation, not a scripted answer.
- The fix's approach — compare `RAWCapabilities` against a freshly constructed `CIRAWFilter` for the same file at test time, rather than pinning historical snapshot values — is the right generalization. It keeps the tests meaningful (still catches a probe that silently falls back to a hardcoded default) while decoupling them from one camera's specific behavior.
- `Fixtures.localRAWURLs` (plural) cleanly generalizes discovery to "every RAW file present" and iterates rather than assuming exactly one fixture exists; each of the three tests degrades to `XCTSkip` only when no fixture is usable for that specific check (byte-classifiable / develop-capable / probeable), not when the fixture list is merely non-empty. That's the correct skip semantics — a machine with fixtures but an incompatible decoder still gets a real, if narrower, signal instead of a false pass.
- Verified the compared fields (`isContrastSupported`, `isDetailSupported`, etc.) exist on `RAWCapabilities` (Sources/LumoKit/Models/RAWCapabilities.swift) and are populated the same way in `RenderEngine.swift`, so the new assertions track production code, not a stale mirror.
- No product code changed — this is test-only, consistent with the issue's acceptance criteria (fix or adjust tests to match correct decoder behavior).

**Note (non-blocking, out of scope for this issue):** `.gitignore` currently has an uncommitted change removing the `realworldtest/` ignore rule, and the two ARW fixtures show as untracked. That's pre-existing working-tree state from other in-flight work, not part of 7d0cfd7 — flagging for awareness only, not filing a child ticket since it doesn't affect this issue's correctness.

No blockers found. Clearing lease and moving to done.

## Agent log

- 2026-09-02T04:50:20.503Z: Verified: root cause confirmed as decoder/fixture capability drift; test-only fix compares live CIRAWFilter output instead of pinned snapshots. Full suite 594/0 failures, 13 skips, matches implementer's report.
