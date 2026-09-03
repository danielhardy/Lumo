---
id: LUMO-080
title: Make tone-curve dragging a smooth real-time curve with live image feedback
type: task
status: done
priority: high
labels:
  - mvp
  - live-preview
  - light
  - ux
created: 2026-09-01T03:00:52.537Z
updated: 2026-09-01T04:34:03.748Z
order: a0
board: product
commits:
  - a72203a
---

## Objective

Make tone-curve dragging feel like direct manipulation: the visible curve should bend smoothly
under the pointer and the edited image should update continuously while the pointer is down.

## Context

The current `ToneCurveEditor` in `Sources/LumoKit/Views/LightInspectorView.swift` draws the
master RGB transfer function from `LightToneCurve.value(at:)`, which is piecewise-linear between
control points. Dragging an interior handle can therefore read as moving a single pivot/kink: the
control point moves, but the UI does not communicate a smooth curve being shaped under the pointer.
The image preview also needs to make each meaningful drag position visible before mouse-up; a
curve edit that only becomes apparent after the gesture is over feels disconnected from both the
graph and the photograph.

This ticket covers the interaction and presentation behavior on top of the existing live-preview
rendering path. Preview and export must continue to consume the same persisted `LightToneCurve`
values so the on-screen result remains authoritative.

## Acceptance criteria

- [ ] Pressing and dragging an interior tone-curve handle updates the handle position and the
  rendered curve continuously on every pointer movement; the line visibly follows the pointer
  before mouse-up.
- [ ] The edited transfer function is rendered as a smooth, shape-preserving curve with a local
  bend around the dragged region, rather than presenting the interaction as a single pivot or a
  visibly angular pair of straight segments. The interpolation must not overshoot or introduce
  tone inversions when the control points are monotonic.
- [ ] Direct manipulation remains predictable: the dragged point stays under the pointer, adjacent
  tones transition smoothly, endpoints remain fixed, and control-point ordering/invariants remain
  valid throughout the gesture.
- [ ] Each intermediate curve state updates the displayed photograph through the live preview
  path while the drag is in progress. The image visibly changes before mouse-up, with no
  mouse-up-only refresh, blank frame, or stale curve revision presented after a newer drag value.
- [ ] Interactive updates remain frame-paced/latest-wins and do not regress the existing bounded
  tone-curve rendering path or allocate a full-resolution image object for every pointer tick.
- [ ] Releasing the pointer settles the final curve without a visual jump, and the settled preview
  and full-resolution export produce the same tone mapping for the final document.
- [ ] Add regression coverage for curve-path updates during a drag, smooth interpolation around a
  moved point, monotonicity/invariant preservation, intermediate preview publication, and preview /
  export parity. Update accessibility behavior if the interaction model changes.

## Implementation notes

- Prefer a shape-preserving cubic or equivalent smooth interpolation that preserves endpoint and
  control-point values and cannot overshoot monotonic input data. Keep the persisted model
  resolution-independent; do not replace it with a UI-only curve that export cannot reproduce.
- The UI curve and renderer must use one shared interpolation definition (or equivalent sampled
  representation) so the line shown in the graph matches the pixels in the photograph.
- Keep the existing undo coalescing semantics: one continuous drag should remain one undo step.
- Relevant code: `Sources/LumoKit/Views/LightInspectorView.swift`,
  `Sources/LumoKit/Models/LightAdjustments.swift`,
  `Sources/LumoKit/ViewModels/AppViewModel+Light.swift`, and the live preview coordinator/surface.

### Comment — codex @ 2026-09-01T04:31:43.582Z

Implemented in commit a72203a. LightToneCurve now uses shared shape-preserving cubic Hermite/PCHIP interpolation for the SwiftUI graph and bounded renderer texture, with exact control-point preservation and monotonic no-overshoot behavior. Tone-curve handles retain stable slot identity during drags, and monotonic curves constrain dragged outputs to neighboring values while preserving input ordering; existing frame-paced/latest-wins live preview and undo coalescing remain in use. Added regression coverage for smoothness, invariants, intermediate interactive publication, and preview/export parity. Verification: swift test (435 passed, 24 skipped), swift build -c release, git diff --check, dg validate OK with known runner/context warnings.

### Comment — claude @ 2026-09-01T04:34:00.212Z

## Counterpoint verification — PASS

Independent review of commit a72203a (smooth tone-curve live editing), after human review.

**Checks run (all green):**
- `swift build` — clean.
- `swift build -c release` — clean.
- `swift test` — 435 passed, 24 skipped, 0 failures (matches the implementer's reported numbers exactly).
- `git diff --check` on the diff — no whitespace/conflict-marker issues.

**Correctness review of `LightToneCurve.value(at:)` (PCHIP/Hermite):**
- Endpoint slope formula and interior weighted-harmonic-mean slope formula both match the standard Fritsch–Carlson three-point/weighted-harmonic PCHIP derivation.
- Sign/overshoot limiter on endpoint slopes matches the textbook PCHIP guard (zero out on sign mismatch with the adjacent delta; clamp to 3× the endpoint delta on local extrema).
- Degenerates correctly to linear interpolation for 2-point curves (no spurious curvature at min configuration).
- Final `min/max` clamp against `[lower.output, upper.output]` is a legitimate FP-safety net on top of an already-guaranteed-monotonic PCHIP result — not covering for a broken limiter.
- Exact-knot case (`x == upper.input`) is special-cased to return the stored value directly, avoiding any FP round-trip through the Hermite basis at a control point.

**Shared interpolation / preview-export parity:** confirmed `RenderPipeline.applyToneCurve` → `ToneCurveFilterCache` samples the same `LightToneCurve.value(at:)` used by the SwiftUI `Canvas` graph in `LightInspectorView` — one definition, no drift path. This file was untouched by the commit, so parity is inherited "for free" from the shared function change, consistent with the ticket's shared-definition requirement.

**Drag-time invariant clamp in `AppViewModel+Light.moveToneCurvePoint`:** the new `constrainedOutput = min(max(output, points[index-1].output), points[index+1].output)` branch is gated on `isMonotonic`, which this codebase defines as non-decreasing (`$0.output <= $1.output`), so the ordering assumption baked into that min/max clamp is safe — it would silently misbehave for a general (non-decreasing-assumed) definition, but that's not what `isMonotonic` means here.

**ForEach identity fix** (`id: \.offset` instead of `id: \.input`) is a real bug fix: keying handle views by `input` would tear down/rebuild the drag gesture on every pointer tick as the point's `input` changes, which is exactly the kind of thing that would make a drag look laggy/broken. Offset-based identity is safe here because interior points stay sorted and the slot count only changes on add/remove, not per drag tick.

**Test coverage:** new tests directly exercise the acceptance criteria — smooth local bend + C1 continuity at a handle, no-overshoot across a full swept sample of a 3-point monotonic curve, drag-time ordering/bounding invariants, and an intermediate (pre-mouse-up) interactive publication reaching the preview coordinator with the in-flight curve value. All pass.

No blocking or backlog-worthy findings. No code changes made during this verification pass (implementation already correct).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-01T04:34:03.747Z: Independent verification passed: build/release/tests all green (435 passed/24 skipped), PCHIP interpolation math verified correct, shared value(at:) confirmed as single source for graph+renderer parity, ForEach identity fix confirmed as a real bug fix, drag-time monotonic clamp verified sound. No blockers.
