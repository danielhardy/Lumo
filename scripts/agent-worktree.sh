#!/usr/bin/env bash
#
# agent-worktree.sh — create/remove a throwaway git worktree for agent or
# multi-agent workflow runs, so they operate on an isolated checkout and can
# never mutate the main working tree. See CLAUDE.md "Agent & workflow safety".
#
# Usage:
#   DIR=$(scripts/agent-worktree.sh create [ref])   # create on `ref` (default: current HEAD); prints path
#   scripts/agent-worktree.sh list                  # list active worktrees
#   scripts/agent-worktree.sh remove <path>         # remove a worktree created above
#
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cmd="${1:-}"

case "$cmd" in
  create)
    ref="${2:-HEAD}"
    # Detached checkout in a temp dir → no branch to collide, nothing to push.
    dir="$(mktemp -d "${TMPDIR:-/tmp}/lumo-agent-XXXXXX")"
    git -C "$repo_root" worktree add --detach "$dir" "$ref" >&2
    echo "$dir"
    ;;
  list)
    git -C "$repo_root" worktree list
    ;;
  remove)
    target="${2:-}"
    if [ -z "$target" ]; then
      echo "usage: $0 remove <path>" >&2
      exit 2
    fi
    git -C "$repo_root" worktree remove --force "$target"
    git -C "$repo_root" worktree prune
    ;;
  *)
    echo "usage: $0 {create [ref] | list | remove <path>}" >&2
    exit 2
    ;;
esac
