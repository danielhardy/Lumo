#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

icon_set="Sources/Lumo/Assets.xcassets/AppIcon.appiconset"
source_svg="Sources/Lumo/Branding/LumoIcon.svg"
info_plist="Sources/Lumo/Info.plist"
asset_output=".build/lumo-icon-asset-validation"
app_bundle=".build/Lumo.app"

[[ -f "$source_svg" ]] || { print -u2 "missing icon source: $source_svg"; exit 1; }
[[ -f "$info_plist" ]] || { print -u2 "missing bundle metadata: $info_plist"; exit 1; }
[[ -d "$icon_set" ]] || { print -u2 "missing icon catalog: $icon_set"; exit 1; }

mkdir -p "$asset_output" "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

# Render each catalog slot from the same vector source. `sips` is part of the
# Apple toolchain and preserves the SVG's square canvas at exact pixel sizes.
for spec in 16@1 16@2 32@1 32@2 128@1 128@2 256@1 256@2 512@1 512@2; do
  size="${spec%@*}"
  scale="${spec#*@}"
  pixels=$((size * scale))
  output="$icon_set/icon_${size}x${size}@${scale}x.png"
  /usr/bin/sips -s format png -z "$pixels" "$pixels" "$source_svg" --out "$output" >/dev/null
done

# Build the executable through SwiftPM, then put it in a normal macOS bundle.
# SPM intentionally has no app-bundle Info.plist phase, so this small
# packaging step is the reproducible bridge used by local/archive workflows.
swift build -c release --product Lumo
bin_path="$(swift build -c release --show-bin-path)"
cp "$bin_path/Lumo" "$app_bundle/Contents/MacOS/Lumo"

/usr/bin/actool "$icon_set" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$asset_output/asset-info.plist" \
  --compile "$app_bundle/Contents/Resources" >/dev/null

cp "$info_plist" "$app_bundle/Contents/Info.plist"

print "Built $app_bundle"
