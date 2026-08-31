---
id: LUMO-064
title: "Resolve merge conflict: agent/lumo-018 ImageCollection.swift vs. thumbnail scheduler on main"
type: task
status: done
priority: urgent
labels:
  - verification
created: 2026-08-31T14:47:48.412Z
updated: 2026-08-31T15:19:15.920Z
order: zzh
board: product
branch: agent/lumo-064
---

## Parent

LUMO-018 (verification child; see its comment thread for full context).

## Objective

Integrate branch `agent/lumo-018` (PhotoAsset stable-identity records, commits `0961319`, `0d14f3d`)
into `main`. The automatic merge attempted by `dg issue complete` failed:

```
Auto-merging README.md
Auto-merging Sources/LumoKit/Models/ImageCollection.swift
CONFLICT (content): Merge conflict in Sources/LumoKit/Models/ImageCollection.swift
Automatic merge failed; fix conflicts and then commit the result.
```

## Root cause

`agent/lumo-018`'s merge-base is `50f80a3`. Since then, `main` picked up a sibling line of work
(`ee28124` "Integrate prioritized thumbnail scheduling" and its ancestors `f2c9ee6`, `cfda50b`) that
is **not** an ancestor of `50f80a3` — a different rewrite of `ImageCollection`'s thumbnail pipeline
(introducing `ImageWorkScheduler`, job IDs, prioritized/reprioritized thumbnail loading,
`select(at:)`, signposts) that touches the same regions of
`Sources/LumoKit/Models/ImageCollection.swift` as LUMO-018's `PhotoAsset`-based `Item` rework.
`README.md` also conflicts (both branches added a paragraph in the same spot).

This is a real three-way merge between two independent feature reworks of the same file, not a
mechanical/localized conflict — it needs a human or an agent with authority to reconcile product
behavior (should the merged `Item`/`PhotoAsset` structure also carry the `ImageWorkScheduler`
job-ID/priority fields introduced on `main`?).

## Scope

- Rebase or merge `agent/lumo-018` onto current `main`, reconciling `ImageCollection.Item`/`PhotoAsset`
  with the `ImageWorkScheduler`-based thumbnail pipeline already on `main`.
- Resolve the `README.md` conflict (both additions are worth keeping, in some order).
- Re-run `swift build`, `swift test`, `swift build -c release`, `dg validate` after resolution.
- Land the merge as a normal PR/merge commit per `CLAUDE.md`'s "Code changes land via the normal
  flow" rule — do not force-resolve by discarding either branch's feature.

## Verification

- Full test suite green post-merge.
- Manually confirm `ImageCollection` still produces stable `PhotoAssetID`s per LUMO-018's acceptance
  criteria *and* still exercises the prioritized-thumbnail scheduler from the sibling work.
