# Lumo

Native macOS RAW photo editor

This project is managed with DispatchGraph. Its Markdown issues and YAML configuration are the
source of truth; local runtime data lives under `.project/` and can be regenerated.

## Start with an issue

```bash
dg board
dg issue create "Describe the first change"
dg issue prepare LUMO-001
dg ready --next
```

Prepared issues move to `ready`, where they can be claimed manually or picked up by a configured
local agent. Review `AGENTS.md` before asking an agent to work: it contains this project's
generated lifecycle, claim, and Git-workflow instructions.

## Agent entry points

```bash
dg doctor                    # check configured runner binaries and pickup configuration
dg agent setup               # print portable MCP configuration for an IDE agent
dg pickup                    # watch Ready work and launch the configured local runner
dg serve                     # open the local web board for this project
```

Before pickup or MCP use, authenticate the chosen agent CLI once in this project terminal.
`dg doctor` checks binary availability and configuration, but not login state. If this project
uses approval-bypass pickup settings, run it only in a workspace you trust.

## Project files

- `dg.yaml` — project settings
- `AGENTS.md` — generated instructions for coding agents
- `boards/` — board definitions
- `issues/` — one markdown file per issue
- `assets/` — image attachments referenced from issue Markdown
- `docs/` — durable documentation
- `decisions/` — architecture decision records
- `.project/` — events + local index (disposable runtime files)
- `.gitattributes` — `merge=union` for append-only `.project/events.jsonl`

Optional web board (`dg serve`): **Runs** for local pickup control, **Settings** for agent
diagnostics.
