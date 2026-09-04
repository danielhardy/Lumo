#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

app_bundle="${1:-.build/Lumo.app}"
[[ -d "$app_bundle" ]] || { print -u2 "missing $app_bundle; run scripts/build-macos-app.sh first"; exit 1; }

/usr/bin/codesign --verify --deep --strict "$app_bundle"
dump="$(mktemp -t lumo-entitlements).plist"
trap 'rm -f "$dump"' EXIT
/usr/bin/codesign -d --entitlements :- "$app_bundle" > "$dump" 2>/dev/null

python3 - "$dump" "$app_bundle" <<'PY'
import pathlib
import plistlib
import sys

entitlements_path, app_dir = map(pathlib.Path, sys.argv[1:])
try:
    entitlements = plistlib.loads(entitlements_path.read_bytes())
except Exception as exc:
    raise SystemExit(f"could not decode embedded entitlements: {exc}")

expected = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.files.removable-media.read-only": True,
    "com.apple.security.files.bookmarks.app-scope": True,
}
for key, value in expected.items():
    if entitlements.get(key) != value:
        raise SystemExit(f"entitlement {key!r} is {entitlements.get(key)!r}, expected {value!r}")

print(f"verified strict code signature and {len(expected)} expected entitlements on {app_dir}")
PY
