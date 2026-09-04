---
id: LUMO-205
title: Visual regression harness
type: task
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:58.024Z
updated: 2026-09-04T14:34:46.287Z
depends_on:
  - LUMO-204
order: zzzzzzz
board: product
---

**Type:** Task
**Component:** new developer tooling (script or Swift executable — implementer's choice)
**Depends on:** LUMO-204
**Epic:** LUMO-181 — see original proposal §40

## 1. Problem

Golden semantic tests (LUMO-204) catch regressions in *facts*, not perceptual regressions in
Auto's actual visual output. A visual regression harness — before/after/diff/mask-overlay per
fixture, rendered into one report — lets a human or agent see at a glance whether a change helped
or hurt, across the whole corpus.

## 2. Requirement (acceptance criteria)

1. A runnable tool that, for every fixture in LUMO-204's corpus: renders the original, runs
   `AutoLightEngine` (LUMO-200) and renders the result, computes a diff, includes the relevant
   mask overlay (reuse LUMO-203's or LUMO-201's overlay-rendering logic, whichever exists), and
   includes `AutoRationale` (LUMO-200).
2. Output is a single browsable artifact (an HTML report is simplest), written to a predictable,
   non-committed location.
3. Runnable as a single command; document it in the ticket's completion comment.
4. Not wired into CI — a human/agent-facing dev tool, not a gate.
5. Swift 6 clean if implemented in Swift.

## 3. Implementation notes

- Keep this pragmatic — a static HTML grid is sufficient; no server, no JS framework needed.

## 4. Where to look

- LUMO-204's fixture corpus, LUMO-200's `AutoLightEngine`/`AutoRationale`, LUMO-201/203's overlay
  logic.

## 5. Testing

- Run it against the corpus and confirm the report renders correctly for at least one fixture from
  each scenario category.
