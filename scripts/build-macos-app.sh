#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

icon_set="Sources/Lumo/Assets.xcassets/AppIcon.appiconset"
asset_catalog="Sources/Lumo/Assets.xcassets"
source_svg="Sources/Lumo/Branding/LumoIcon.svg"
info_plist="Sources/Lumo/Info.plist"
entitlements="Sources/Lumo/Lumo.entitlements"
asset_output=".build/lumo-icon-asset-validation"
app_bundle=".build/Lumo.app"
signing_identity="${LUMO_CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
provisioning_profile="${LUMO_PROVISIONING_PROFILE:-${PROVISIONING_PROFILE:-}}"

[[ -f "$source_svg" ]] || { print -u2 "missing icon source: $source_svg"; exit 1; }
[[ -f "$info_plist" ]] || { print -u2 "missing bundle metadata: $info_plist"; exit 1; }
[[ -f "$entitlements" ]] || { print -u2 "missing entitlements: $entitlements"; exit 1; }
[[ -d "$icon_set" ]] || { print -u2 "missing icon catalog: $icon_set"; exit 1; }
if [[ -n "$provisioning_profile" && ! -f "$provisioning_profile" ]]; then
  print -u2 "configured provisioning profile does not exist: $provisioning_profile"
  exit 1
fi

# Generate into disposable paths so packaging never mutates tracked source assets.
rm -rf "$asset_output" "$app_bundle"
staged_asset_catalog="$asset_output/Assets.xcassets"
staged_icon_set="$staged_asset_catalog/AppIcon.appiconset"
mkdir -p "$asset_output" "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp -R "$asset_catalog" "$staged_asset_catalog"

# Render each catalog slot from the same vector source. `sips` is part of the
# Apple toolchain and preserves the SVG's square canvas at exact pixel sizes.
for spec in 16@1 16@2 32@1 32@2 128@1 128@2 256@1 256@2 512@1 512@2; do
  size="${spec%@*}"
  scale="${spec#*@}"
  pixels=$((size * scale))
  output="$staged_icon_set/icon_${size}x${size}@${scale}x.png"
  /usr/bin/sips -s format png -z "$pixels" "$pixels" "$source_svg" --out "$output" >/dev/null
done

# Build the executable through SwiftPM, then put it in a normal macOS bundle.
# SPM intentionally has no app-bundle Info.plist phase, so this small
# packaging step is the reproducible bridge used by local/archive workflows.
swift build -c release --product Lumo
bin_path="$(swift build -c release --show-bin-path)"
cp "$bin_path/Lumo" "$app_bundle/Contents/MacOS/Lumo"

/usr/bin/actool "$staged_asset_catalog" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$asset_output/asset-info.plist" \
  --compile "$app_bundle/Contents/Resources" >/dev/null

cp "$info_plist" "$app_bundle/Contents/Info.plist"

if [[ -n "$provisioning_profile" ]]; then
  cp "$provisioning_profile" "$app_bundle/Contents/embedded.provisionprofile"
fi

# Sign after every distributed resource is present. '-' is the documented local/CI
# fallback and still embeds the declared entitlements.
codesign_args=(--force --sign "$signing_identity" --entitlements "$entitlements")
if [[ "$signing_identity" != "-" ]]; then
  codesign_args+=(--timestamp)
fi
/usr/bin/codesign "${codesign_args[@]}" "$app_bundle"
/usr/bin/codesign --verify --deep --strict "$app_bundle"

print "Built and verified $app_bundle (identity: $signing_identity)"
