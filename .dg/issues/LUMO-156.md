---
id: LUMO-156
title: Replace Look color swatches with photo thumbnails showing the applied Look
type: feature
status: ready
priority: medium
labels:
  - looks
  - ux
  - preview
  - verification
created: 2026-09-03T14:41:57.393Z
updated: 2026-09-03T14:55:06.497Z
order: a0
board: product
---

## Objective

Replace the non-informative color swatches beside Looks with small photo previews
that show what each Look does to an image.

## Context

The Look list currently shows each Look with a narrow color gradient derived from
LUT samples. Those colors do not communicate the photographic result, so users must
apply Looks one at a time to understand their character. Photo-editing experiences
commonly use an image thumbnail with the Look applied, which makes comparison and
selection much faster.

The preferred preview is a bounded thumbnail of the current photo/source with each
Look applied. A deliberate fallback is needed when no photo is available or when a
preview cannot be rendered. Relevant current UI and LUT code is in
`Sources/LumoKit/Views/LookInspectorView.swift`, `Sources/LumoKit/Models/CubeLUT.swift`,
and the preview/render coordinators under `Sources/LumoKit/ViewModels/`.

## Acceptance criteria

- [ ] Each Look row shows a recognizable photo thumbnail with that Look applied,
      rather than only a color gradient; the thumbnail is approximately 100 px tall
      or uses an equivalent compact size that fits the inspector cleanly.
- [ ] Thumbnails make meaningful visual comparison possible while preserving the
      existing Look name, selected state, intensity controls, and apply behavior.
- [ ] Preview generation is bounded and cached/lazy enough that scrolling a Look list
      does not trigger full-resolution renders or noticeable UI stalls.
- [ ] The preview uses the current photo when one is loaded and has a clear,
      deterministic fallback for the empty/no-photo and render-failure states.
- [ ] Bundled, imported, and user-saved Looks all receive the same preview treatment;
      missing or invalid LUTs fail gracefully without breaking the list.
- [ ] Preview thumbnails expose useful accessibility labels or remain hidden from
      VoiceOver when the Look name and state already provide the information.
- [ ] Add automated coverage for preview selection/fallback, caching or render
      bounds, and representative Look-row layout at supported inspector widths.

## Implementation notes

Keep the preview non-destructive: it must not modify the active edit document or
history. Reuse the existing render pipeline and downsample before display; do not
duplicate the full source image per Look. Resolve the product/design details during
implementation: exact thumbnail height/aspect ratio, crop policy, whether previews
update when the selected photo changes, and whether a static sample image is needed
as the no-photo fallback. Preserve the macOS 14 and zero-third-party-dependency
constraints.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
