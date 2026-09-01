# Inspector disclosure smoke test

The Light, Color, and Effects inspectors use `InspectorDisclosure` for every expandable section.
This is a manual interaction check for the macOS app, including the nested sections that are not
covered by the model test suite.

## Section matrix

| Inspector | Top-level rows | Nested rows |
| --- | --- | --- |
| Light | Tone, Tone Curve | — |
| Color | White Balance, Color, Color Mixer / HSL, Color Grading | Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta; Shadows, Midtones, Highlights |
| Effects | Texture / Clarity / Dehaze, Vignette, Grain | — |

## Steps and expected results

1. Open each inspector and click the title text, then the empty trailing part of the same row.
   Each click toggles only that row, and the chevron rotates smoothly with the content.
2. Repeat while a section contains edited controls. Expansion and collapse retain the control values,
   do not clip the last control, and do not move the scroll position unexpectedly.
3. Expand Color Mixer / HSL and Color Grading. Toggle several channel/zone rows in turn; a nested
   row changes only itself and never toggles its parent. Repeat with the parent while a child is open.
4. With focus on each title row, press Space and Return. Both keys toggle the focused row, and focus
   remains usable after the content appears or disappears.
5. In VoiceOver, navigate to each title row. It is announced as a toggle with an `Expanded` or
   `Collapsed` value, and the standard toggle action changes only that section.
