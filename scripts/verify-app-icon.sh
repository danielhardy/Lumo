#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

icon_set="Sources/Lumo/Assets.xcassets/AppIcon.appiconset"
contents="$icon_set/Contents.json"
app_bundle=".build/Lumo.app"

[[ -f "$contents" ]] || { print -u2 "missing AppIcon Contents.json"; exit 1; }
[[ -d "$app_bundle" ]] || { print -u2 "missing $app_bundle; run scripts/build-macos-app.sh first"; exit 1; }

python3 - "$contents" "$icon_set" "$app_bundle" <<'PY'
import json
import pathlib
import plistlib
import struct
import sys

contents_path, icon_dir, app_dir = map(pathlib.Path, sys.argv[1:])
data = json.loads(contents_path.read_text())
images = data.get("images", [])
expected = {(s, scale) for s in ("16x16", "32x32", "128x128", "256x256", "512x512") for scale in ("1x", "2x")}
seen = set()

if len(images) != len(expected):
    raise SystemExit(f"AppIcon must contain exactly {len(expected)} macOS slots, found {len(images)}")

for entry in images:
    key = (entry.get("size"), entry.get("scale"))
    if entry.get("idiom") != "mac" or key not in expected:
        raise SystemExit(f"invalid AppIcon slot metadata: {entry}")
    filename = entry.get("filename")
    if not filename or pathlib.Path(filename).name != filename:
        raise SystemExit(f"slot has no safe image filename: {entry}")
    image_path = icon_dir / filename
    if not image_path.is_file():
        raise SystemExit(f"missing AppIcon image: {image_path}")
    raw = image_path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"not a PNG: {image_path}")
    width, height = struct.unpack(">II", raw[16:24])
    pixels = int(entry["size"].split("x")[0]) * int(entry["scale"].rstrip("x"))
    if (width, height) != (pixels, pixels):
        raise SystemExit(f"wrong dimensions for {image_path}: {(width, height)} != {(pixels, pixels)}")
    seen.add(key)

if seen != expected:
    raise SystemExit(f"AppIcon slots incomplete: missing {sorted(expected - seen)}")

info = plistlib.loads((app_dir / "Contents/Info.plist").read_bytes())
if info.get("CFBundleIconName") != "AppIcon":
    raise SystemExit("application target does not reference AppIcon")
if not (app_dir / "Contents/Resources/Assets.car").is_file():
    raise SystemExit("compiled application is missing Contents/Resources/Assets.car")
if not (app_dir / "Contents/MacOS/Lumo").is_file():
    raise SystemExit("compiled application is missing Contents/MacOS/Lumo")

print(f"verified {len(images)} AppIcon slots, valid PNG dimensions, CFBundleIconName=AppIcon, and Assets.car")
PY
