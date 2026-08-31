---
id: LUMO-060
title: Update stale LUTzy/LUTzyKit paths in living reference docs
type: task
status: backlog
priority: low
labels:
  - verification
created: 2026-08-30T19:11:59.143Z
updated: 2026-08-30T19:12:08.208Z
order: zzz
board: product
---

## Objective

Update `Sources/LUTzyKit/...` path references and `LUTzy` module names in living reference
documentation so they match the post-rename tree (LUMO-002, commit c1feab7).

## Context

Verification of LUMO-002 (rename LUTzy → Lumo) found the rename itself clean: build/test pass,
no application- or package-facing `LUTzy` identifiers remain in `Sources/`, `Tests/`,
`Package.swift`, entitlements, CI, scripts, or bundle-facing strings.

However, two docs that CLAUDE.md treats as **living** references (not attribution/history) still
reference the old module/paths:

- `docs/PHASE2_SPEC.md` — "the implementation plan for the non-destructive render pipeline"
  (CLAUDE.md: "keep it a distillation"), still says `LUTzyKit` throughout.
- `docs/CODE_REVIEW.md` — "records the standing review findings: what was fixed, and what is
  still open" (CLAUDE.md), still titled "LUTzy — code review" and references `LUTzyKit`.

These are distinct from `.context/initial_concept.md` and `docs/superpowers/plans/*.md`, which are
dated historical transcripts of already-completed steps and were correctly left alone.

## Scope

- Update `docs/PHASE2_SPEC.md` and `docs/CODE_REVIEW.md`: replace `LUTzy`/`LUTzyKit` module/path
  references with `Lumo`/`LumoKit` where they describe current/ongoing state.
- Leave `.context/initial_concept.md` and `docs/superpowers/plans/*.md` untouched (historical).

## Acceptance criteria

- [ ] `docs/PHASE2_SPEC.md` and `docs/CODE_REVIEW.md` reference `LumoKit`/`Lumo` paths, not `LUTzyKit`/`LUTzy`.
- [ ] No content/decision history is rewritten — path/module names only.

## Out of scope

- Editing `.context/initial_concept.md` or `docs/superpowers/plans/*.md`.
