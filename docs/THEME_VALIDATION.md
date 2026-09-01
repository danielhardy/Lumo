# Theme validation smoke test

Lumo intentionally does not set `preferredColorScheme`; the window inherits the macOS appearance.
The shell uses dynamic AppKit named colors, while the histogram, tone curve, and Metal image
letterbox retain explicitly scoped dark analysis/presentation backdrops.

On macOS 14 or newer:

1. Set **System Settings → Appearance → Light**, launch Lumo, and verify the empty state, toolbar,
   inspector, Look browser, library, filmstrip, status bar, and any loading state use a light
   surface with readable primary and secondary text.
2. Open an image and a source folder. Visit the Info histogram, Light tone curve, Look browser,
   and library grid; confirm the analysis plots remain legible without turning their parent panes
   dark.
3. With the window still open, switch **Appearance** to **Dark**. Confirm all shell surfaces and
   text update without relaunching; repeat the reverse transition back to Light.
4. Repeat steps 1–3 starting in Dark appearance, including an empty launch and a loading/scanning
   state.

The test passes when both launch appearances match the system and each live transition updates all
visible shell surfaces while keeping the intentionally dark analysis/presentation surfaces legible.
