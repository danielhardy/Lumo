#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

app_bundle="${1:-.build/Lumo.app}"
if [[ ! -d "$app_bundle" ]]; then
  print -u2 "missing $app_bundle; run scripts/build-macos-app.sh first"
  exit 1
fi

# Hosted macOS runners may not have a logged-in WindowServer session. The CI job still invokes this
# path, but leaves the decision to run it to the session rather than producing a false application
# failure from an unavailable accessibility service.
if ! /usr/bin/osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
  print "SKIP: no accessible macOS UI session for application smoke test"
  exit 2
fi

smoke_dir="$(mktemp -d -t lumo-app-smoke)"
input_png="$smoke_dir/input.png"
output_png="$smoke_dir/export.png"
app_pid=""
cleanup() {
  if [[ -n "$app_pid" ]]; then
    /usr/bin/osascript -e 'tell application "Lumo" to quit' >/dev/null 2>&1 || true
    kill "$app_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$smoke_dir"
}
trap cleanup EXIT

/usr/bin/sips -s format png -z 256 256 Sources/Lumo/Branding/LumoIcon.svg --out "$input_png" >/dev/null
open -n "$app_bundle"

for _ in {1..30}; do
  app_pid="$(pgrep -x Lumo | head -1 || true)"
  [[ -n "$app_pid" ]] && break
  sleep 1
done
[[ -n "$app_pid" ]] || { print -u2 "Lumo did not launch"; exit 1; }

if ! /usr/bin/osascript -e 'tell application "Lumo" to activate' >/dev/null 2>&1; then
  print "SKIP: macOS refused to activate Lumo through the UI automation service"
  exit 2
fi

export LUMO_SMOKE_INPUT="$input_png"
export LUMO_SMOKE_OUTPUT="$output_png"
/usr/bin/osascript <<'APPLESCRIPT'
set inputPath to do shell script "printf '%s' \"$LUMO_SMOKE_INPUT\""
set outputPath to do shell script "printf '%s' \"$LUMO_SMOKE_OUTPUT\""

using terms from application "System Events"
on waitForWindow(p)
    repeat 30 times
        if (count of windows of p) > 0 then return
        delay 1
    end repeat
    error "Lumo did not create a window"
end waitForWindow

on clickFileMenuItem(p, itemName)
    set fileMenu to menu 1 of menu bar item "File" of menu bar 1 of p
    click menu bar item "File" of menu bar 1 of p
    set targetItem to (first menu item of fileMenu whose title is itemName)
    click targetItem
end clickFileMenuItem
end using terms from

tell application "System Events"
    tell application "Lumo" to activate
    tell process "Lumo"
        my waitForWindow(it)

        -- Open through the shipping File menu and native Open panel.
        my clickFileMenuItem(it, "Open Image...")
        repeat 20 times
            if (count of sheets of window 1) > 0 then exit repeat
            delay 1
        end repeat
        set openSheet to sheet 1 of window 1
        set value of text field 1 of openSheet to inputPath
        click button "Open" of openSheet

        repeat 30 times
            if (count of windows) > 0 then exit repeat
            delay 1
        end repeat

        -- Exercise the application-level Settings scene, then return to the main window.
        click menu bar item "Lumo" of menu bar 1
        set lumoMenu to menu 1 of menu bar item "Lumo" of menu bar 1
        set settingsItem to (first menu item of lumoMenu whose title contains "Settings")
        click settingsItem
        delay 2
        if (count of windows) < 2 then error "Settings did not open"
        keystroke "w" using command down
        delay 1

        -- Export through the File menu and native Save panel.
        my clickFileMenuItem(it, "Export...")
        repeat 20 times
            if (count of sheets of window 1) > 0 then exit repeat
            delay 1
        end repeat
        set saveSheet to sheet 1 of window 1
        set value of text field 1 of saveSheet to outputPath
        click button "Save" of saveSheet
        delay 3
    end tell
end tell
APPLESCRIPT

[[ -s "$output_png" ]] || { print -u2 "application smoke export was not created: $output_png"; exit 1; }
print "Application smoke passed: launch, open, Settings, File menu, and export"
