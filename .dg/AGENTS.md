# AGENTS.md — Lumo

This project is managed with DispatchGraph: markdown issues, YAML boards, and an MCP tool contract.

## Agent setup

- Supported agents: cursor, claude, opencode, codex, pi.
- Default claim actor: `codex`.
- Skip permission prompts on pickup for: cursor, claude, opencode, codex, pi.
- Pickup is enabled (`dg pickup`) with runner `codex` (model `gpt-5.6-luna`).
- Yolo mode is enabled: pickup skips the human review gate by automatically promoting successful `review` handoffs to `verification`. Agents should still hand off to `review` normally.
- Each claim picked up by `dg pickup` runs in its own git worktree (`./dg-worktrees/<issue-id>`), so concurrent claims and a human working in the main checkout do not block each other.
- The live DispatchGraph space (nested `.dg`) is linked into each worktree; use CLI/MCP from the worktree cwd as usual. `DG_SPACE_ROOT` also points at the live space.
- Worktree pickup installs Node.js dependencies only (npm, pnpm, yarn, bun when package.json is present). Other stacks (Python, Ruby, Java, Swift, etc.) are not installed automatically — agents must set up each worktree themselves.
- Counterpoint verification is enabled; default verifier: `claude` (model `sonnet`).
- Pickup automatically moves successful implementation handoffs from `review` to `verification`, releases the implementation lease, and launches the verifier.
- Verification uses its own process pool (max 1), independent from implementation pickup (max 1); worktrees isolate checkouts, but API spend and local services remain shared.
- Verifiers review correctness, maintainability, security, and performance; apply only localized safe fixes; create `verification`-labeled child tickets for broader findings; return blockers to `review`; pass by completing to `done`.
- Verified issue branches are auto-merged into `main` when verification completes (`agents.verification.merge_on_done`).

## Quick start for agents

1. Prefer MCP tools (`project_get_next_work`, `project_claim_issue`, `project_get_context`) when available.
2. Or use the CLI: `dg next`, `dg issue claim <id>`, `dg context <id>`.
3. Canonical records live in `issues/*.md` (inside the dg space) — edit frontmatter carefully.
4. Append-only history is in `.project/events.jsonl`.
5. Do not invent a parallel task tracker.

## Status lifecycle

`backlog → ready → claimed → review → verification → done`

## Claiming work

Always claim before starting. Claims expire (default 60 minutes). Release if you lose context.

## Comments

When commenting (`dg issue comment` or MCP `project_add_comment`), pass `actor` set to your
agent name (e.g. `cursor`, `claude`, `codex`) — never let it default to `human`. If omitted, it
falls back to the `DG_ACTOR` environment variable, then the issue's active claim agent, then
`agents.default_actor`.

## Git workflow

- Work directly on the current branch — claims do not assign a per-issue branch or worktree (`git.branch_per_issue` is off).
- Keep the working tree to **one issue** at a time — do not pile unrelated tickets into the same session.
- Commit coherent work on the current branch when the change is ready for review.
- Implementation agents move the issue to `review` with a short summary comment. Do **not** mark `done` or merge unless a human or CI asks you to.
- Verification agents continue in the same working tree using the project Git mode; on pass they may complete to `done` after appending a structured report.
- Push or open a PR only when a human asks or project policy clearly allows it (`git.mode` is manual and `auto_commit` is off by default).

## Context

Each issue may declare `context.files`, `context.docs`, `context.issues`, and `context.commands`.
Request a budgeted context package instead of reading the whole repository.
