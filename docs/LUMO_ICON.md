# Lumo product icon

`Sources/Lumo/Branding/LumoIcon.svg` is the canonical source artwork. It is an
original Lumo mark made from geometric paths and gradients; it uses no external
fonts, stock art, logos, or third-party assets. It is covered by the repository's
MIT License.

## Construction and export

- Source canvas: 1024 × 1024 points/pixels.
- Safe area: x/y 128…896 (75% of the canvas); the macOS icon mask trims the
  outer rounded-square background, not the mark.
- The cool navy-violet field keeps the mark distinct on light, dark, and
  automatic macOS appearances. The warm disc and cyan/lilac beam retain
  contrast without depending on text or fine detail.
- PNGs are rendered from the SVG with `/usr/bin/sips`, then validated and
  compiled with `/usr/bin/actool` by `scripts/build-macos-app.sh`.

The SVG is intentionally kept as an input rather than checked in as a catalog
asset: Xcode's asset compiler consumes the generated PNGs listed in
`AppIcon.appiconset/Contents.json`, and the script makes the conversion
reproducible on a macOS build host.

## Review checklist

Inspect `LumoIcon.svg` at 1024 px and the generated 16, 32, and 128 px PNGs.
The 16 px rendering should read as a bright disc over an open L; no lettering
or sub-pixel detail is required. Check both Finder/Dock light and dark
appearances, then launch the built app and confirm the same icon is shown in
the window, Dock, and Finder.

## Build and verify

```sh
scripts/build-macos-app.sh
scripts/verify-app-icon.sh
```

The build script writes only to `.build/Lumo.app` and `.build/lumo-icon-asset-
validation`; both are generated build outputs. The checked-in
`Sources/Lumo/Info.plist` sets `CFBundleIconName=AppIcon`, and `actool` compiles the catalog into
`Contents/Resources/Assets.car`.
