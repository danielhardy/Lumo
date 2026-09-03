# Theme validation smoke test

Lumo applies the persisted **Always dark mode** preference at the `NSWindow` level through
`LumoWindowAppearanceController`. This reaches the already-open main window, Settings, sheets,
and child views in both SwiftUI scenes. When the preference is off, the controller clears the
window override so AppKit inherits the macOS appearance. The shell uses dynamic AppKit named
colors, while the histogram, tone curve, and Metal image letterbox retain explicitly scoped dark
analysis/presentation backdrops.

On macOS 14 or newer:

1. Set **System Settings → Appearance → Light**, launch Lumo, and verify the empty state, toolbar,
   inspector, Look browser, library, filmstrip, status bar, and any loading state use a light
   surface with readable primary and secondary text.
2. Open an image and a source folder. Visit the Info histogram, Light tone curve, Look browser,
   and library grid; confirm the analysis plots remain legible without turning their parent panes
   dark.
3. With the window still open, open **Lumo → Settings**, enable **Always dark mode**, and confirm
   the Settings panel and every main-window shell surface update without relaunching or recreating
   the window. Disable it again and confirm the app returns to macOS-following appearance.
4. With **Always dark mode** enabled, close and reopen Settings, open a sheet, and relaunch Lumo;
   confirm all app-shell windows remain consistent. Repeat with the preference disabled and macOS
   set to Light and Dark.

The test passes when both launch appearances match the system and each live transition updates all
visible shell surfaces while keeping the intentionally dark analysis/presentation surfaces legible.
