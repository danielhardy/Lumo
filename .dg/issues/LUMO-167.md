---
id: LUMO-167
title: "Audit: cap and stream user-provided Cube LUT parsing"
type: bug
status: done
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - security
  - robustness
  - lut
  - audit
created: 2026-09-03T23:28:48.865Z
updated: 2026-09-04T02:47:25.673Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: File size, line length, metadata volume, and supported LUT dimensions are bounded before allocation.
      result: pass
      notes: maximumFileBytes/maximumLineBytes/maximumMetadataBytes/maximumMetadataLines are checked via FileManager attributes and the LUTLineReader before any table allocation; LUT_3D_SIZE is validated against minimumSupportedSize...maximumSupportedSize before expected row count or capacity is derived.
    - criterion: Parsing is incremental or otherwise avoids retaining the complete source text and line array.
      result: pass
      notes: LUTLineReader streams the file through a FileHandle in bounded 64KB chunks, yielding one line at a time; the parser never builds a full-file String or line array, and floats is reserved once at expected*4 and appended row by row.
    - criterion: Parsing stops after the expected size^3 rows and rejects trailing excess safely.
      result: pass
      notes: Once floats.count == expected*4, any further data row, keyword, or unknown metadata line throws invalidFormat("trailing content after the expected table entries") or an equivalent must-appear-before-table-data error; only comments/blank lines remain accepted post-table, still bounded by the metadata budget.
    - criterion: Tests cover oversized files, oversized lines, excessive metadata, truncated data, and valid 65^3 files.
      result: pass
      notes: "CubeLUTTests: testRejectsOversizedFileBeforeParsingItsContents, testRejectsAnOversizedLineWhileStreaming, testRejectsExcessiveMetadataBeforeAllocatingTable, testRejectsOversizedCubeBeforeAllocatingTable, testWrongEntryCountThrows (truncated/short table), testRejectsTrailingTableRowsAfterTheDeclaredCube, testParsesTheMaximumSupported65CubeIncrementally."
  checks_run:
    - swift test --filter CubeLUTTests (26 passed)
    - swift test (full suite, exit 0)
    - swift build -c release
    - git diff --check
    - dg validate
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T02:47:25.666Z
  session: 01MTMCN5B930L5KXKS
---

## Objective

Bound resource use while parsing user-provided `.cube` and `.look` LUT files.

## Context

`CubeLUT` loads the entire file into a `String` and splits every line before validating the declared size and row count. A malformed or unexpectedly large user-selected file can consume excessive memory and CPU before it is rejected.

## Acceptance criteria

- [ ] File size, line length, metadata volume, and supported LUT dimensions are bounded before allocation.
- [ ] Parsing is incremental or otherwise avoids retaining the complete source text and line array.
- [ ] Parsing stops after the expected `size³` rows and rejects trailing excess safely.
- [ ] Tests cover oversized files, oversized lines, excessive metadata, truncated data, and valid 65³ files.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-04T02:43:03.654Z

Implemented in cba880b. CubeLUT now checks file size, line length, metadata budgets, and the 2...65 dimension range before bounded allocation; parses through a chunked FileHandle reader into the final RGBA table; rejects truncation and trailing semantic content after size³ rows. Added oversized file/line/metadata, trailing-row, and valid 65³ coverage. Verification: swift test --filter CubeLUTTests (26 passed), swift test (732 passed, 14 skipped, 0 failures), swift build -c release, git diff --check, dg validate.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T02:47:25.671Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] File size, line length, metadata volume, and supported LUT dimensions are bounded before allocation. (pass) — maximumFileBytes/maximumLineBytes/maximumMetadataBytes/maximumMetadataLines are checked via FileManager attributes and the LUTLineReader before any table allocation; LUT_3D_SIZE is validated against minimumSupportedSize...maximumSupportedSize before expected row count or capacity is derived.
- [x] Parsing is incremental or otherwise avoids retaining the complete source text and line array. (pass) — LUTLineReader streams the file through a FileHandle in bounded 64KB chunks, yielding one line at a time; the parser never builds a full-file String or line array, and floats is reserved once at expected*4 and appended row by row.
- [x] Parsing stops after the expected size^3 rows and rejects trailing excess safely. (pass) — Once floats.count == expected*4, any further data row, keyword, or unknown metadata line throws invalidFormat("trailing content after the expected table entries") or an equivalent must-appear-before-table-data error; only comments/blank lines remain accepted post-table, still bounded by the metadata budget.
- [x] Tests cover oversized files, oversized lines, excessive metadata, truncated data, and valid 65^3 files. (pass) — CubeLUTTests: testRejectsOversizedFileBeforeParsingItsContents, testRejectsAnOversizedLineWhileStreaming, testRejectsExcessiveMetadataBeforeAllocatingTable, testRejectsOversizedCubeBeforeAllocatingTable, testWrongEntryCountThrows (truncated/short table), testRejectsTrailingTableRowsAfterTheDeclaredCube, testParsesTheMaximumSupported65CubeIncrementally.
Checks run:
- swift test --filter CubeLUTTests (26 passed)
- swift test (full suite, exit 0)
- swift build -c release
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTMCN5B930L5KXKS
Summary: Verified: CubeLUT parsing checks file size, per-line length, metadata line/byte budgets, and the 2...65 dimension range before allocating the table; a bounded FileHandle-backed LUTLineReader streams line-by-line into the final RGBA float array (single allocation, sized once LUT_3D_SIZE is known) without ever retaining the full source text or a line array. Parsing stops rows at size^3 and rejects any further semantic content (data rows, keywords, or unknown metadata) as trailing excess; only comments/blank lines remain accepted after the table, bounded by the shared metadata budget. Re-ran locally: swift test --filter CubeLUTTests (26 passed, covering oversized file/line/metadata, oversized cube, reversed domain, truncated/short table, trailing rows, and a real 65^3 cube), full swift test (exit 0), swift build -c release, git diff --check, dg validate — all pass. No blockers; no fixes needed.
