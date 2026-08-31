# AGENTS.md — Lumo

This project is managed with DispatchGraph: markdown issues, YAML boards, and an MCP tool contract.

## Agent setup

- Supported agents: cursor, claude, opencode, codex, pi.
- Default claim actor: `codex`.
- Skip permission prompts on pickup for: cursor, claude, opencode, codex, pi.
- Pickup is enabled (`dg pickup`) with runner `codex` (model `gpt-5.6-luna`).
- Worktree isolation is disabled; claims share the current checkout. Do not run more than one claim against this working tree at a time.
- The live DispatchGraph space is used from the current checkout; `DG_SPACE_ROOT` points at the live space.
- Counterpoint verification is enabled; default verifier: `claude` (model `sonnet`).
- After human review, moving an issue to `verification` releases the implementation lease and launches the verifier through the same pickup process.
- Verifiers review correctness, maintainability, security, and performance; apply only localized safe fixes; create `verification`-labeled child tickets for broader findings; return blockers to `review`; pass by completing to `done`.
- Do not merge issue branches. Work lands as commits on the current branch; `merge_on_done` is off.

## Quick start for agents

1. Prefer MCP tools (`project_get_next_work`, `project_claim_issue`, `project_get_context`) when available.
2. Or use the CLI: `dg next`, `dg issue claim <id>`, `dg context <id>`.
3. Canonical records live in `issues/*.md` (inside the dg space) — edit frontmatter carefully.
4. Append-only history is in `.project/events.jsonl`.
5. Do not invent a parallel task tracker.

## Status lifecycle

`backlog → ready → claimed → review → verification → done`

## Claiming work

Always claim before starting, passing the current branch from `git branch --show-current`. Claims expire (default 60 minutes). Release if you lose context.

## Comments

When commenting (`dg issue comment` or MCP `project_add_comment`), pass `actor` set to your
agent name (e.g. `cursor`, `claude`, `codex`) — never let it default to `human`. If omitted, it
falls back to the `DG_ACTOR` environment variable, then the issue's active claim agent, then
`agents.default_actor`.

## Git workflow

- Tickets run **sequentially on the current branch**. Each ticket is one commit on that branch, not its own branch.
- Stay on the branch that is already checked out. Do not create, switch to, or merge a per-issue branch.
- Keep the working tree to **one issue** at a time. Finish and commit it before claiming the next.
- Do **not** commit during implementation. Leave uncommitted work in the tree until the issue is ready for review.
- When moving the issue to `review`, first create **one coherent commit** of that issue's work on the current branch. The message should reference the issue id.
- Implementation agents move the issue to `review` with a short summary comment. Do **not** mark `done` or merge unless a human or CI asks you to.
- Verification agents continue in the same working tree using the project Git mode; on pass they may complete to `done` after appending a structured report.
- Push or open a PR only when a human asks or project policy clearly allows it (`git.mode` is manual and `auto_commit` is off by default).

## Implementation handoff termination

After the implementation is complete, verified, and committed:

1. Add the required completion comment.
2. Transition the issue to `review` using the documented DispatchGraph command.
3. Stop immediately after the handoff succeeds.

Do not inspect or modify DispatchGraph lifecycle bookkeeping after handoff. In particular, do not inspect events or verifier activity, reconcile or repair board state, commit lifecycle changes, run additional status checks, or attempt to advance the issue beyond `review`. DispatchGraph owns all subsequent lifecycle transitions.

## Context

Each issue may declare `context.files`, `context.docs`, `context.issues`, and `context.commands`.
Request a budgeted context package instead of reading the whole repository.
