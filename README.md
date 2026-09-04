<div align="center">

# Lumo

### A native macOS RAW photo editor — develop, grade, and export on Apple's own stack.

Lumo is a fast, non-destructive photo workflow for RAW and standard images. It is built with
SwiftUI, Core Image, Metal, AppKit, PhotosUI, Swift Charts, ImageIO, and `simd` — with **zero
third-party dependencies**.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Core%20Image-9cf)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![GPU](https://img.shields.io/badge/rendering-Metal--accelerated-success)

</div>

---

## What is Lumo?

Lumo is a native macOS RAW editor organised around a real photo workflow:

1. **Import** a folder, individual image, drag-and-drop payload, or up to 50 Photos assets.
2. **Cull** in a grid-first Library workspace with picks, rejects, star ratings, filters, and
   multi-selection.
3. **Edit** each photo non-destructively through a shared value-based document and render pipeline.
4. **Compare** the edited result with a develop-applied baseline, or inspect it on a pannable,
   zoomable canvas.
5. **Export** the current photo or the whole collection at full source resolution.

Every edit is stored as data, never as a baked preview bitmap. Preview and export use the same
pipeline, so the image on screen and the image written to disk follow the same edit order.

Lumo is also an agent-driven software project. Agents plan, claim, implement, verify, and advance
work through [DispatchGraph](.dg/README.md), making the development process part of the experiment.

## Fork and attribution

Lumo began as a fork of [LUTzy](https://github.com/tsvb/lutzy), an MIT-licensed macOS LUT
color-grading app. The original copyright notice and [MIT License](LICENSE) are retained. The fork
provided the initial `.cube` parsing/application, RAW decoding, folder/export plumbing, Look
derivation, and much of the original test foundation; the current product and package targets are
Lumo's own.

---

## Features

### Import and library workflow

- Native RAW/DNG decoding through Core Image's `CIRAWFilter`, plus JPEG, PNG, TIFF, BMP, and HEIC.
- RAW extensions: `DNG`, `CR2`, `CR3`, `NEF`, `ARW`, `ORF`, `RAF`, `RW2`, `PEF`, `SRW`, `X3F`, and
  `RAW`.
- Drag in a single image or a folder; choose a source folder (`⌘⌥I`) for recursive scanning,
  subfolder grouping, remembered folder access, and re-scan (`⌘R`).
- Streaming Photos import (`⌘⇧I`), capped at 50 selections, with cancellation and partial-failure
  handling so successful transfers remain usable.
- Grid-first Library workspace with a virtualized mosaic, async thumbnails, stable asset identities,
  multi-select, and double-click-to-edit navigation.
- Pick/reject flags, 0–5 star ratings, and combined culling filters for All, Picks, Rejected, and
  rating ranges.
- Edit workspace with a filmstrip, docked source browser, keyboard navigation, canvas pan/zoom,
  Fit/Fill, and resettable panel sections.

### Non-destructive editing

Each photo has a `Codable`, `Sendable`, `Equatable` `EditDocument`. Its current stages are:

- **RAW Develop** — decoder-native exposure, baseline exposure, shadow bias, tone curve, white
  balance, sharpness, contrast/detail, moiré and noise reduction, lens correction, gamut mapping,
  extended dynamic range, and highlight recovery. Controls are probed and shown only when the
  current decoder supports them; values start from that file's own defaults.
- **Light** — Exposure, Contrast, Highlights, Shadows, Whites, Blacks, and a master RGB tone curve.
- **Color** — RAW-aware white balance, Vibrance, Saturation, an eight-channel HSL mixer
  (Red/Orange/Yellow/Green/Aqua/Blue/Purple/Magenta), and three-way Shadows/Midtones/Highlights
  color grading with blending and balance.
- **Effects** — Texture, Clarity, Dehaze, post-crop Vignette (Amount, Midpoint, Roundness, Feather,
  Highlights), and deterministic film Grain (Amount, Size, Roughness).
- **Crop** — freeform, non-destructive framing in normalized oriented-image coordinates. Draft
  geometry is transient until Apply; preview and full-resolution export use the same crop.
- **Look** — an optional `.cube` 3D LUT with adjustable intensity.

Individual controls and whole sections can be reset. Slider gestures use an interactive render path
and become one undo entry when committed; numeric fields and resets use the settled path.

### Looks and LUTs

- Parses standard `.cube` 3D LUTs, including `LUT_3D_SIZE` and `DOMAIN_MIN`/`DOMAIN_MAX`.
- Applies LUTs through `CIColorCubeWithColorSpace` with Metal-backed Core Image rendering.
- Ships four original, read-only starter Looks across Monochrome, Cinematic, Film-inspired, and
  Warm slide-inspired categories. Provenance, licensing, attribution, redistribution, and approval
  records live in [`docs/STARTER_LOOKS.md`](docs/STARTER_LOOKS.md) and the bundled manifest.
- Scans a Look folder recursively, groups files by subfolder, supports search and None, and keeps
  folder access through App Sandbox security-scoped bookmarks.
- Imports external `.cube` and `.look` files (`⌘⌥L`) and refreshes the library after files are
  replaced externally.
- Stores a stable Look reference in the edit document, so a rescan does not silently change the
  selected Look. Missing references are reported while the stored edit is preserved.

### Derive a Look from a JPG

Lumo can manufacture a portable `.cube` Look from a camera RAW and its straight-out-of-camera JPG.
Use `File ▸ Derive Look from JPG…` (`⌘D`) to choose the pair. Lumo renders the RAW through the
same neutral `CIRAWFilter` baseline used by the editor, validates the pair's aspect ratio, aligns
the images, masks JPEG edges, samples smooth regions, and builds a smoothed 33³ cube.

The report includes:

- Per-channel tone curves against identity.
- Saturation and measured sharpening ratios. Sharpening is reported but not baked into a LUT.
- Cube coverage and surviving sample count.
- Camera make/model and relevant JPEG EXIF picture-style fields.
- Alignment information and a Swift Charts visualization.

The derived Look previews immediately as a scratch result. **Save to Look Folder…** makes it a
library Look; the stable derived identity keeps the edit resolving across rescans.

### Compare, inspect, and export

- Single-view and side-by-side comparison (`V`) share the same render source. Hold `Space` to show
  the develop-applied photo without the visible Light/Color/Effects/Look edits; crop framing is
  retained.
- Info inspector (`⌘I`) shows a live RGB/luma histogram and EXIF, TIFF, and GPS metadata.
- Export the edited document as 16-bit TIFF, JPEG, or PNG. The format is selected in the save flow
  and the last choice is retained for the session.
- Single export (`⌘S`) and Export All (`⌘⇧E`) render from the original source at full resolution.
  Export All continues past individual failures and reports the completed/skipped counts.
- Output names include the photo name and selected Look, with collision-safe suffixes.

---

## Persistence and editing state

Edits are isolated per photo and survive navigation and relaunch. Lumo stores a versioned JSON edit
catalog under the user's Application Support directory; writes are serialized, coalesced during
slider activity, atomically replaced, and backed up. The store also supports:

- Up to 100 undo and redo snapshots per photo, containing only value-state documents.
- Copy/paste of all edits between photos, including destinations that were never opened.
- Recovery from a corrupt primary catalog using the last known-good backup.
- Relinking a moved source through its stored bookmark/locator and re-keying the record.
- Schema-version checks that refuse to overwrite edits written by a newer Lumo build.
- A termination flush so queued edits are durable before the app exits.

Source records use stable filesystem identities where available and cache fingerprints include file
metadata/content sampling. Photos imports use the Photos local identifier when supplied; data-only
imports use a SHA-256 identity for the delivered bytes.

## Keyboard shortcuts

| Key | Action |
|---|---|
| `G` | Switch to Library |
| `E` | Switch to Edit |
| `Return` | Open the active Library item in Edit |
| `P` | Mark the focused photo as Pick and advance |
| `X` | Mark the focused photo as Reject and advance |
| `0`–`5` | Clear or set the focused photo's star rating |
| `←` / `→` or `[` / `]` | Previous / next image |
| `↑` / `↓` | Previous / next Look |
| `V` | Toggle single-view / side-by-side comparison |
| `Space` (hold) | Show the comparison baseline |
| `⌘I` | Toggle the Info inspector |
| `⌘O` | Open an image |
| `⌘⇧I` | Import from Photos |
| `⌘⌥I` | Open a source folder |
| `⌘R` | Re-scan the source folder |
| `⌘⇧L` | Choose a Look folder |
| `⌘⌥L` | Import Look files |
| `⌘D` | Derive a Look from a JPG |
| `⌘Z` / `⌘⇧Z` | Undo / redo |
| `⌘⇧R` | Reset the current photo |
| `⌘⌥C` / `⌘⌥V` | Copy / paste all edits |
| `⌘S` | Export |
| `⌘⇧E` | Export all |

Arrow, letter, culling, and comparison shortcuts are routed by a window-level `NSEvent` monitor so
they work across the split view. They yield to text fields, sliders, buttons, pickers, system
modifiers, and the derive sheet.

---

## Build, run, and test

Lumo is a Swift Package; there is no `.xcodeproj` to maintain.

### Requirements

- **Run:** macOS 14.0 or newer.
- **Build:** Xcode 26 or newer with the macOS 26 SDK.
- **Language mode:** Swift 6.

The deployment target and build SDK are intentionally different. The package deploys to macOS 14,
while the current RAW capability surface requires the macOS 26 SDK to compile. Availability checks
keep newer APIs optional at runtime.

### Commands

```bash
# Build and launch the executable target for quick iteration.
swift run

# Build a release product.
swift build -c release

# Run the test suite.
swift test
```

`swift run` launches the bare Swift Package executable. It does not include the bundled asset
catalog or App Sandbox entitlements, so the app icon and security-scoped bookmark persistence are
not active in that mode. For bundled app behavior, open `Package.swift` in Xcode, select the
**Lumo** scheme, and run. The included [`Lumo.entitlements`](Sources/Lumo/Lumo.entitlements) is
configured for user-selected read/write access, read-only access to mounted removable media, and
app-scope bookmarks.

The removable-media import flow is intentionally read-only. `MountedMediaVolumeProvider` discovers
supported files on mounted removable/ejectable volumes under the removable-media entitlement; it
does not write to the source volume. The provider still attempts
`startAccessingSecurityScopedResource()` because a caller may supply a scoped URL, but raw mount
URLs are normally entitlement-authorized rather than security-scoped. If macOS does not authorize
a particular volume class from the entitlement alone, Lumo keeps the volume visible, asks the user
to select its root in an Open panel, and scans the resulting security-scoped bookmark. Run the full
Xcode-built app to verify this path; `swift run` does not apply the entitlement.

The suite currently contains **574 XCTest methods**. Fixtures are generated in temporary
directories; RAW-dependent tests may use files under `realworldtest/` and skip cleanly when a
required RAW/JPG pair is unavailable. CI runs a debug build, tests, and a release build on every
push and pull request using the macOS 26 runner.

Optional local benchmarks:

```bash
# Coalesced edit persistence across 10, 1,000, and 10,000-record catalogs.
LUMO_PERSISTENCE_BENCHMARK=1 swift test --filter EditPersistenceBenchmarkTests

# Real CAMetalLayer drawable presentation and input-to-presentation latency.
LUMO_METAL_BENCHMARK=1 swift test --filter MetalPresentationBenchmark/testRealMetalPresentationBenchmark

# The same real drawable benchmark using a released RAW fixture.
LUMO_METAL_BENCHMARK=1 \
LUMO_METAL_BENCHMARK_RAW=/absolute/path/to/realworldtest/DSC07826.ARW \
swift test -c release --filter MetalPresentationBenchmark/testRealMetalPresentationBenchmark

# Automated xctrace capture with Points of Interest + Metal System Trace.
scripts/run-lumo-118-capture.sh realworldtest/DSC07826.ARW

# Tracing overhead with and without an active Instruments recording.
LUMO_TRACE_BENCHMARK=1 swift test --filter TracingOverheadBenchmark/testMeasureTracingOverhead
```

Hardware latency claims require a logged-in display and a Release build; the opt-in Metal benchmark
does not turn CI timings into a product claim. See [Instruments capture recipe](docs/INSTRUMENTS.md)
and the [performance audit](docs/PERFORMANCE_AUDIT_2026-09-01.md) for capture procedure, limits,
and the current matrix.

---

## Architecture

The package is split into a thin executable and a testable `LumoKit` library:

```text
Sources/
├── Lumo/
│   ├── LumoApp.swift           # @main app, window, delegate, termination flush
│   ├── Assets.xcassets/        # app icon and accent color
│   └── Lumo.entitlements       # sandbox file access and bookmarks
└── LumoKit/
    ├── Models/                 # value state, image sources, pipeline, caches, persistence
    ├── ViewModels/             # AppViewModel and export/derive/preview coordinators
    └── Views/                  # Library, canvas, filmstrip, inspectors, menus, status bar

Tests/
└── LumoKitTests/               # model, pipeline, integration, regression, and opt-in benchmarks

docs/                           # architecture, validation, profiling, and audit records
```

The important boundaries are:

- **Value document:** `EditDocument` contains RAW develop settings, Light, Color, Effects, crop,
  legacy ordered adjustment nodes, and the Look reference. Empty state is the identity transform.
- **One graph, multiple qualities:** `RenderPipeline` folds the document into one lazy Core Image
  graph. `RenderEngine` evaluates it at interactive, preview, thumbnail, or full quality; preview
  and export differ by an explicit quality/output policy rather than separate edit logic.
- **Deterministic stage order:** source/develop → Light → Color → ordered adjustments → Look → crop
  → post-crop vignette → deterministic grain. This keeps spatial effects aligned with the final
  frame while preserving preview/export parity.
- **Actor isolation:** Core Image objects stay inside the render engine. Sendable values cross the
  boundary, and the package compiles in Swift 6 language mode without unchecked concurrency escapes.
- **GPU presentation:** live previews use a persistent Metal-backed presentation surface. Interactive
  edits are debounced/coalesced, stale work is discarded, and a valid last frame is retained when a
  replacement fails.
- **Bounded work:** developed-source, render, LUT, and thumbnail caches are bounded and respond to
  memory pressure. Thumbnail work is prioritized around the visible library neighborhood.
- **Coordinators:** `AppViewModel` owns app state while dedicated preview, export, derive, and
  persistence collaborators keep expensive or file-dialog work off the main actor.
- **Observability:** signposts and bounded live telemetry distinguish input, render, GPU completion,
  and actual drawable presentation so profiling does not confuse “render finished” with “user saw
  the frame.”

Useful starting points are [`EditDocument`](Sources/LumoKit/Models/EditDocument.swift),
[`RenderPipeline`](Sources/LumoKit/Models/RenderPipeline.swift),
[`RenderEngine`](Sources/LumoKit/Models/RenderEngine.swift), and
[`EditDocumentStore`](Sources/LumoKit/Models/EditDocumentStore.swift).

## Preparing for the App Store

1. Build and verify the product icon and signed bundle with [`scripts/build-macos-app.sh`](scripts/build-macos-app.sh), [`scripts/verify-app-icon.sh`](scripts/verify-app-icon.sh), and [`scripts/verify-app-signature.sh`](scripts/verify-app-signature.sh); see [`docs/LUMO_ICON.md`](docs/LUMO_ICON.md) for the source, safe area, and review checklist. Packaging renders into `.build/` and does not modify the tracked catalog.
   Release signing uses `LUMO_CODESIGN_IDENTITY` (or `CODE_SIGN_IDENTITY`) and optionally `LUMO_PROVISIONING_PROFILE` (or `PROVISIONING_PROFILE`). If neither is set, the script uses an ad-hoc signature for local/CI structural verification; configure the release identity and profile in CI for distribution builds.
2. Set the Bundle Identifier and Team in Xcode's Signing & Capabilities.
3. Keep App Sandbox enabled with the included entitlements.
4. Use **Product ▸ Archive ▸ Distribute App ▸ App Store Connect**.

## License

Lumo is released under the [MIT License](LICENSE). The LUTzy fork attribution and original license
terms are preserved as described above.

<div align="center">
<sub>Built with SwiftUI · Core Image · Metal — and nothing else.</sub>
</div>
