---
id: LUMO-132
title: Investigate intermittent CropWorkflowTests.testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit failure
type: bug
status: done
priority: low
verification_agent: pi
verification_model: openrouter/z-ai/glm-5.3-flash
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - d2c24bc
  actor: pi
  resolved_model: openrouter/z-ai/glm-5.3-flash
  completed_at: 2026-09-02T19:00:16.479Z
  session: 01MTKGFGCWUWOH0ESN
labels:
  - verification
created: 2026-09-02T12:56:07.207Z
updated: 2026-09-02T19:00:16.708Z
parent: LUMO-124
order: a0
board: product
commits:
  - d2c24bc
---

## Objective

Investigate intermittent CropWorkflowTests.testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit failure

## Context

Surfaced repeatedly as an unrelated pre-existing flake during independent verification of other
tickets (LUMO-107, LUMO-121, and now LUMO-124's verification pass). Reproduced directly: running
the test alone 3x in a row on the pre-LUMO-124 parent commit (955cc36, in a scratch worktree)
failed 1 of 3 runs with the same assertion — "reopening Crop must render the full source stage,
not the already-cropped committed frame" — confirming it predates and is independent of LUMO-124's
crop-drag change. It has never had its own tracking ticket; each ticket that hits it just notes it
inline and moves on.

## Acceptance criteria

- [ ] Root-cause the intermittent failure (timing/ordering dependency in the fake render engine's
      request capture, most likely, per the assertion message).
- [ ] Either fix the flake or make the test deterministic (e.g. await the specific render request
      instead of racing it).
- [ ] `swift test --filter CropWorkflowTests` passes reliably across repeated runs (10+) with no
      failures.

## Implementation notes

Look at `CropWorkflowTests.testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit` in
Tests/LumoKitTests/CropTests.swift and how it inspects `FakeRenderEngine.previewRequests`. See
LUMO-115 (which introduced this test) for the original intent.

### Comment — pi @ 2026-09-02T14:43:36.132Z

Reproduced again during LUMO-128 verification (commit fe187c8, unrelated change): 2 of 3 consecutive full `swift test` runs failed this test with the same assertion at CropTests.swift:218 ("reopening Crop must render the full source stage, not the already-cropped committed frame"); the other full run and 3 isolated re-runs (`swift test --filter CropWorkflowTests/testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit`) passed. Failure appears only under full-suite load, consistent with the timing-sensitive hypothesis already recorded here.

### Comment — codex @ 2026-09-02T18:53:28.064Z

Implemented in commit b42facf. Root-caused the flake to count-only synchronization: superseded preview work can still be captured after the baseline, so a count increase does not identify the requested transition. The regression test now waits for the committed preview before taking its baseline and awaits post-action requests matching the expected crop state for re-entry and cancel. Verification: 10 repeated swift test --filter CropWorkflowTests runs (40 tests) passed; CropPipelineTests, ComparisonModeTests, full swift test (630 passed, 14 expected skips), swift build -c release, git diff --check, and dg validate passed.

### Comment — pi @ 2026-09-02T19:00:13.989Z

Counterpoint verification (pi): PASS.

Reviewed the fix in commit b42facf. The root-cause diagnosis is correct: previewRequests is an append-only actor log, so a count-only wait could be satisfied by a superseded request (e.g. the still-in-flight committed-crop preview) landing after beginCrop(). The fix addresses it at both layers: (1) the re-entry baseline is taken only after the committed preview has been observed, and (2) post-baseline waits match on semantic predicates (crop.isIdentity for re-entry, crop == committed for cancel) via waitForPreviewRequest(after:matching:on:predicate:) instead of log growth. Index baselines are safe because the log is never trimmed. No blockers found.

One localized follow-up applied in commit d2c24bc: the pre-existing waitUntil helper interpolated its timeout message as the literal '(description)'; fixed to \(description). Test-only, no behavior change.

Checks run:
- swift build --build-tests: clean.
- swift test --filter CropWorkflowTests: 10/10 consecutive runs passed (acceptance criterion met).
- Full swift test: 630 tests, 0 failures, 14 expected skips, under full-suite load (the condition under which the flake originally reproduced).

Verification commits: d2c24bc. No child tickets filed; no open findings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-02T19:00:16.480Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- d2c24bc
Actor: pi
Resolved model: openrouter/z-ai/glm-5.3-flash
Pickup session: 01MTKGFGCWUWOH0ESN
Summary: Verified b42facf: semantic predicate waits + post-commit baseline make the re-entry crop test deterministic. 10/10 filtered runs and a full swift test (630 tests, 0 failures) passed. Follow-up commit d2c24bc fixed a broken timeout-message interpolation in waitUntil.
