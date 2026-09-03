---
id: LUMO-133
title: Give feedback when a clicked Look row fails to resolve
type: bug
status: review
priority: low
labels:
  - verification
created: 2026-09-02T14:42:15.755Z
updated: 2026-09-02T14:56:39.133Z
parent: LUMO-128
order: a0
board: product
---

## Objective

Make a click on a Look row whose LUT cannot be resolved produce observable, actionable feedback in every state, instead of silently doing nothing.

## Context

Surfaced during verification of LUMO-128 (commit fe187c8). `AppViewModel.selectLook(id:)` resolves the clicked ID via `resolvedLUT(_:)`; when resolution fails it either sets a "still loading" `statusMessage` (while `library.isScanning`) or calls `refreshLUTResolutionStatus()` — which reports only on the *document's* persisted `lutID`. Gaps:

- If the active photo has no Look (or a resolved one), clicking a row that has just become unresolvable (e.g. a stale row rendered from a pre-rescan category snapshot) is completely silent: no status message, no selection change.
- Unlike the persisted-missing-reference path (which keeps the ID and shows the inspector's recovery notice), a clicked-but-unresolvable ID is neither selected nor reported, so the user cannot reach the "Clear Look Reference" affordance for it.
- During a scan the "still loading" status asks the user to retry manually; nothing retries or re-renders when the scan completes.

The window is narrow (rows normally exist only for resolvable entries, and parsed `CubeLUT`s stay in memory between rescans), so this is polish, not a correctness bug — LUMO-128's acceptance criterion 4 is met for the primary cases.

## Acceptance criteria

- [ ] Clicking a Look row that cannot resolve produces visible feedback naming that Look (status message or inspector notice), regardless of the active photo's current LUT state.
- [ ] The behavior composes with the existing persisted-missing-reference notice and does not clear or overwrite a more relevant message.
- [ ] Either the pending selection is retried when `library.isScanning` finishes, or the message is cleared/replaced once the clicked Look becomes resolvable.
- [ ] Regression coverage for the unresolvable-click path in each document state (no Look, resolved Look, unresolved persisted Look).
