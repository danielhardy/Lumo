<div align="center">

# Lumo

### A native macOS RAW photo editor — develop, grade, and export on Apple's own stack.

A fast, native macOS app for working with RAW and standard photos: non-destructive develop and
adjust controls, `.cube` LUTs, full-resolution export — built entirely on Apple frameworks with
**zero third-party dependencies**.

> **An agent-driven software project.** Lumo is not just written by agents; it is driven by them
> through [DispatchGraph](.dg/README.md). Agents plan and claim work, implement changes, verify
> results, and advance the product through a shared issue graph — making the development process
> part of the experiment, not just the code it produces.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Core%20Image-9cf)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![GPU](https://img.shields.io/badge/rendering-Metal--accelerated-success)

</div>

---

## What is Lumo?

Lumo is a native macOS RAW photo editor built entirely on Apple frameworks — **SwiftUI** for the
interface, **Core Image** (Metal-backed) for every pixel operation, and **zero third-party
dependencies**. It is organised around the photographer's workflow:

1. **Open a folder of photos** — native RAW/DNG demosaicing plus all the usual formats, with
   asynchronous thumbnails so a large folder is browsable immediately.
2. **Browse and select** — a filmstrip, a docked source-folder browser, and keyboard navigation
   step through the set while your edits stay applied as you go.
3. **Edit non-destructively** — every edit is a small value, not a baked bitmap: RAW develop
   controls, tone and colour adjustments, and an optional `.cube` LUT compose into one render
   pipeline that preview and export share. The original file is never touched.
4. **Export at full quality** — 16-bit TIFF, JPEG, or PNG rendered from the original source plus
   your edit, never from a downscaled preview.

The long-term goal is the full photographer's workflow: Lightroom-style **Light, Color, and
Effects** panels, culling with ratings/picks, copy-edits between photos, and edits that survive a
relaunch. The current build ships the foundation for all of it — see [What ships
today](#what-ships-today) for exactly where things stand.

## Fork & attribution

Lumo began as a fork of [LUTzy](https://github.com/tsvb/lutzy), an MIT-licensed macOS LUT
color-grading app. The original project's copyright notice and the [MIT License](LICENSE) are
retained unchanged, and much of Lumo's machinery comes from that fork: `.cube` parsing and GPU
application, RAW decoding, folder/export plumbing, the LUT-derivation tool below, and most of the
test suite.

References to LUTzy in this repository are **historical** — they describe where Lumo came from.
The product, its package targets (`Lumo`, `LumoKit`), and its identifiers are Lumo's own.

---

## ✨ Features

### Open anything
- **Native RAW/DNG** via Core Image's `CIRAWFilter` — proper demosaicing, not just the embedded preview.
- Supported RAW: `DNG`, `CR2`, `CR3`, `NEF`, `ARW`, `ORF`, `RAF`, `RW2`, `PEF`, `SRW`, `X3F`, `RAW`.
- Standard formats: `JPEG`, `PNG`, `TIFF`, `BMP`, `HEIC`.
- **Drag & drop** a single image *or* a whole folder onto the window.
- **Import from Photos** (up to 50 at once) or **import a folder** straight from the toolbar.

### Browse in batches
- Point Lumo at a **source folder** (**`⌘⌥I`**) and it scans recursively, groups by subfolder, and remembers the choice across launches. **`⌘R`** re-scans.
- A **filmstrip** appears along the bottom, with async-generated thumbnails; a docked **source browser** lists the same set as files.
- **`←` / `→`** (or **`[` / `]`**) step through the set; your current edit stays applied as you go.

Each discovered photo is represented by a stable, Codable value record. File records prefer the
macOS filesystem resource identifier (with a canonical-path fallback), while their cache key also
includes file statistics and a bounded content sample so a replaced file cannot reuse stale derived
state. A Photos import that supplies a local identifier uses that identifier; the current data-only
picker path uses the SHA-256 of the delivered bytes. Consequently, identical data-only payloads are
intentionally one logical source—callers that need to distinguish two Photos assets must provide
their durable Photos identifiers.

### Edit non-destructively
Every image carries an **edit document** — a small `Codable` value, never a baked bitmap. An empty
document is the identity transform: it renders the source untouched. Preview and export render from
the *same* document, so what you see is what exports.

- **RAW Develop panel** — for RAW sources: exposure, baseline exposure, shadow bias, tone curve,
  white balance (temperature/tint), sharpness/contrast/detail, moiré and noise reduction, lens
  correction, gamut mapping, extended dynamic range, and highlight recovery. Each control appears
  only if the file's decoder offers it, and is seeded from that file's own defaults.
- **Adjust panel** — Exposure (EV), Brightness, Contrast, Saturation, Highlights, Shadows,
  Temperature, Tint, and Vibrance.
- **LUT** — optional, at any intensity; a look is one stage of the edit, not the whole edit.

### Grade with LUTs
- Parses standard `.cube` 3D LUTs (`LUT_3D_SIZE`, `DOMAIN_MIN`/`MAX`) and applies them through `CIColorCubeWithColorSpace` — **fully GPU-accelerated** via Metal.
- **Sidebar library** scans your LUT folder recursively and groups looks by subfolder, with a live search field and a running count.
- **Folder access survives restarts** through App Sandbox security-scoped bookmarks — pick your LUT folder once.
- **`↑` / `↓`** cycles through every LUT in your library with instant preview; the toolbar **intensity slider** (0–100%) blends the look back toward the original.

### Derive a LUT from a JPG
- Most apps *apply* LUTs; Lumo can also **manufacture** one. Point it at a RAW file *and* the camera's straight-out-of-camera JPEG, and it synthesises a `.cube` LUT that turns the neutral RAW into that JPEG's look — bottle your camera's color science (or a borrowed film simulation) and apply it to everything else. See [Derive a LUT from a JPG](#-derive-a-lut-from-a-jpg).

### Compare like you mean it
- **Side-by-side** original vs. edited, or a single full-bleed view — toggle with **`V`**.
- **Hold `Space`** to flash back to the original — develop applied, look removed.

### Inspect what you're looking at
- **Info inspector** (**`⌘I`**) with tabs for a live RGB / luma histogram of the displayed image plus the file's EXIF, TIFF, and GPS metadata; the **Light** panel; **RAW Develop**; and **Adjust**.

### Export at full quality
- **16-bit TIFF**, **JPEG** (q 0.95), or **PNG** — always at full source resolution, rendered from the original plus your edit.
- Output is auto-named `‹photo›_‹LUT name›.‹ext›` when a LUT is in the document.
- **Export All** (**`⌘⇧E`**) applies your current edit to every image in the set and writes them to a folder you pick, skipping (and counting) anything that fails rather than aborting the run.

---

## What ships today

| Capability | Status |
|---|---|
| Non-destructive edit document; preview/export parity by construction | ✅ Shipped |
| RAW Develop panel — decoder-native controls, gated per file | ✅ Shipped |
| Adjust panel — exposure, brightness/contrast/saturation, highlights/shadows, temp/tint, vibrance | ✅ Shipped |
| LUT library + GPU application + intensity | ✅ Shipped (inherited from the fork) |
| Derive a `.cube` LUT from a RAW + JPG pair, with analysis report | ✅ Shipped (inherited) |
| Folder import, filmstrip, source browser, Photos import | ✅ Shipped (inherited) |
| Full-resolution TIFF / JPEG / PNG export, single + batch | ✅ Shipped (inherited) |
| Undo / redo | 🔜 Next — the last open step of the render-pipeline migration |
| Per-photo edit storage, persistence across launches | 🔜 Planned — documents are `Codable` precisely for this |
| Copy / paste edits between photos | 🔜 Planned (MVP goal) |
| Ratings, pick/reject culling + filters | 🔜 Planned (MVP goal) |
| Light panel — photographer-facing tone controls and master RGB curve | ✅ Shipped |
| Full Color / Effects panels in the Lightroom sense | 🔜 Planned (MVP goal) |

---

## 🔬 Derive a LUT from a JPG

This is what makes Lumo unusual. Most apps *apply* LUTs; Lumo can also **manufacture** one.

**The idea:** your camera shot a RAW and, at the same instant, rendered its own JPEG using the manufacturer's color science (or whatever film simulation / picture profile you had dialed in). That JPEG *is* a look. Lumo compares the neutral RAW against that JPEG and bakes the difference into a portable `.cube` file you can apply to any other photo.

**Menu:** `File ▸ Derive LUT from JPG…` (**`⌘D`**) → pick the RAW, pick the JPEG, hit **Derive**.

```
  RAW ──► CIRAWFilter (neutral baseline) ─┐
                                          ├─► align ─► sample smooth regions ─► build 33³ cube ─► .cube
  JPEG ─► decode ─► edge mask ────────────┘                                         │
                                                                                    └─► Analysis report
```

Under the hood the extractor:

1. Renders the RAW through the **same** default `CIRAWFilter` pipeline Lumo uses everywhere — so the derived LUT drops straight back into the normal apply path with no baseline mismatch.
2. Checks the pair actually describes one frame (same aspect ratio) and refuses mismatched files rather than silently stretching one onto the other. Lanczos-scales both onto a common working extent — capped at 3000 px on the long edge, since 200k samples describe the color mapping just as well from a 3000 px render as from a 9000 px one — and finds the integer-pixel alignment by luma cross-correlation.
3. Builds an **edge mask** from the JPEG (so in-camera sharpening can't contaminate the color samples) and draws ~200k samples from smooth regions only.
4. Accumulates them into a **33³ color cube**, smooths any sparse cells from their neighbors, and anchors the rest to identity.

### The analysis report

Every derivation comes with a readout (rendered with Swift Charts) so you understand *what the look actually does*:

| Metric | Meaning |
|---|---|
| **Tone curve** | Per-channel R/G/B input→output mapping, plotted against the identity line |
| **Saturation** | Chroma ratio in smooth regions — `>1` more saturated, `<1` more muted |
| **Sharpening** | High-frequency energy ratio (same operator, same pixels, both images) — **measured but deliberately *not* baked into the LUT** (a LUT can't sharpen; apply it separately if you want to match) |
| **Coverage** | % of cube cells filled by real samples vs. interpolated |
| **Samples** | How many smooth-region pixels survived the edge mask |
| **Camera** | Make / model and EXIF contrast, saturation, sharpness, and white-balance tags from the JPEG |

The result previews live on your current image immediately. It stays a scratch LUT until you click
**Save to LUT Folder…**, at which point it joins your sidebar library like any other `.cube`; the
edit document references it by a stable ID, so the look keeps resolving even after the library is
rescanned.

---

## ⌨️ Keyboard shortcuts

| Key | Action |
|---|---|
| `↑` / `↓` | Previous / next LUT |
| `←` / `→` (or `[` / `]`) | Previous / next image (when a set is loaded) |
| `Space` (hold) | Show original — develop applied, look removed |
| `V` | Toggle side-by-side / single view |
| `⌘I` | Toggle the inspector (Info / Develop / Adjust tabs) |
| `⌘O` | Open image |
| `⌘⇧I` | Import from Photos |
| `⌘⌥I` | Open source folder |
| `⌘R` | Re-scan the source folder |
| `⌘⇧L` | Choose LUT folder |
| `⌘D` | Derive LUT from JPG |
| `⌘S` | Export |
| `⌘⇧E` | Export all |

> Arrow/letter shortcuts are handled by a window-level `NSEvent` monitor (SwiftUI's `.onKeyPress` doesn't fire reliably inside a `NavigationSplitView`); `⌘`-shortcuts flow through the standard menu bar.

---

## 🚀 Build & run

Lumo is a Swift Package — no `.xcodeproj` to manage.

**Quickest (CLI):**
```bash
swift run
```
Builds and launches the app for fast iteration. Note: the SwiftUI executable target runs without the bundled asset catalog or sandbox entitlements, so the app icon and security-scoped bookmark persistence won't be active in this mode.

**Recommended (Xcode) — full app behavior, icon, and App Sandbox:**
```bash
open Package.swift     # or: xed .
```
Then select the **Lumo** scheme and **Run** (`⌘R`). For a sandboxed build, add the **App Sandbox** capability and point it at the included [`Lumo.entitlements`](Sources/Lumo/Lumo.entitlements) (user-selected read/write + app-scope bookmarks).

**Tests:**
```bash
swift test
```
328 tests, no fixtures to download — everything they need is generated into a temp directory. The
handful of tests that want real camera files look for an opt-in `realworldtest/` directory (gitignored)
and skip cleanly without it, as on CI. The suite runs debug build → tests → release build in CI on
every push and PR.

For repeatable launch, photo-switch, slider, cache, histogram, and export profiling, see the
[Instruments capture recipe](docs/INSTRUMENTS.md). Its thresholds are targets to validate with a
trace, not claims that the current build has already met them.

**Requirements:**

|  | |
|---|---|
| **To run Lumo** | macOS **14.0+** — unchanged, and what the deployment target targets |
| **To build Lumo** | **Xcode 26+** (macOS 26 SDK) |

Those are deliberately different. Building against a current SDK while deploying to macOS 14 is the
normal Apple model, and the stricter one: the compiler refuses any API newer than macOS 14 unless it
is `#available`-guarded. One RAW develop control (`CIRAWFilter`'s highlight recovery) only exists in
the macOS 26 SDK, so an older Xcode cannot compile the package — while the app it produces still runs
on macOS 14.

---

## 🗂 Project structure

Lumo is split into a `LumoKit` library and a thin `@main` executable, so the app's own code can be
unit-tested — `@testable` cannot import an executable target.

```
Sources/
├── Lumo/                       # thin entry point only
│   ├── LumoApp.swift           # @main App + AppDelegate — window, default size, commands
│   ├── Assets.xcassets/        # App icon + accent color
│   └── Lumo.entitlements       # App Sandbox + user-selected file access
└── LumoKit/                    # everything of substance
    ├── Models/
    │   ├── AdjustmentControl.swift  # the nine Adjust-panel controls: node mapping, ranges, labels
    │   ├── AdjustmentNode.swift     # closed enum of ordered tone/colour stages (exposure, color
    │   │                            #   controls, highlights/shadows, temp/tint, vibrance)
    │   ├── CubeLUT.swift            # .cube parser + writer → CIColorCube filter (also in-memory init)
    │   ├── DerivedLUTRegistry.swift # LUTs a document can reference that no folder scan produces
    │   ├── EditDocument.swift       # the edit as a value: RAW develop + ordered nodes + LUT reference
    │   ├── ExportFormat.swift       # TIFF / JPEG / PNG, with UTType + file extension
    │   ├── Histogram.swift          # 256-bin per-channel histogram data model
    │   ├── ImageCollection.swift    # multi-image set: source folder, selection, navigation
    │   ├── ImageDecoder.swift       # what Lumo can open, and how to turn it into a CIImage
    │   ├── ImageMetadata.swift      # EXIF/TIFF/GPS read + display formatting for the inspector
    │   ├── ImageSource.swift        # how to reproduce a source (URL/Data + extent) so a RAW can be
    │   │                            #   re-developed per render
    │   ├── LUTFilterCache.swift     # reusable CIColorCubeWithColorSpace filters, keyed by LUT + space
    │   ├── LUTLibrary.swift         # scans the LUT folder, groups by category, bookmark persistence
    │   ├── LUTSettings.swift        # a stable LUT ID (a path string) + intensity, stored in the document
    │   ├── RAWCapabilities.swift    # per-file decoder capabilities; drives which develop controls appear
    │   ├── RAWDevelopSettings.swift # the CIRAWFilter knobs — one optional per knob, nil = decoder default
    │   ├── RecipeExtractor.swift    # (RAW, JPG) → 3D LUT derivation pipeline
    │   ├── RecipeReport.swift       # analysis data model (tone curve, ratios, EXIF camera info)
    │   ├── RenderEngine.swift       # actor owning the CIContext; evaluates a graph at one scale
    │   ├── RenderPipeline.swift     # folds an EditDocument into one lazy CIImage (a pure function)
    │   ├── RenderScale.swift        # preview vs. full — the one argument that differs between them
    │   ├── Thumbnails.swift         # filmstrip/browser thumbnails from embedded previews — no CIContext
    │   └── WorkingSpace.swift       # the one colour space: LUT interpolation + output encoding
    ├── ViewModels/
    │   ├── AppViewModel.swift       # central @MainActor state: source, document, collection, LUT
    │   ├── AppViewModel+Adjust.swift  # the nine Adjust-panel bindings onto document.adjustments
    │   ├── AppViewModel+Develop.swift # develop-panel bindings, seeded from per-file decoder defaults
    │   ├── DeriveCoordinator.swift  # "Derive LUT from JPG" flow, scratch-until-saved result
    │   └── ExportCoordinator.swift  # single + batch export, and the naming they share
    └── Views/
        ├── AdjustInspectorView.swift  # slider rows for the adjust controls (data-driven)
        ├── ContentView.swift          # split-view layout + toolbar                          [public]
        ├── DevelopInspectorView.swift # RAW develop panel — one row per capability the file offers
        ├── FilmstripView.swift        # horizontal thumbnail strip for batches
        ├── InfoInspectorView.swift    # inspector pane: Info (histogram + EXIF) / Develop / Adjust tabs
        ├── KeyboardShortcuts.swift    # window-level NSEvent monitor for arrow/letter keys
        ├── LUTSidebar.swift           # searchable, category-grouped LUT list (sidebar)
        ├── MenuCommands.swift         # File menu + its notification names                   [public]
        ├── PreviewView.swift          # side-by-side / single canvas, drag-drop, badges
        ├── RecipeExtractorSheet.swift # "Derive LUT from JPG" modal (pickers, progress, report)
        ├── RecipeReportView.swift     # analysis card — Swift Charts tone curve + stat badges
        ├── SourceBrowserView.swift    # docked source-folder file list, grouped by subfolder
        └── StatusBar.swift            # status line + key hints along the bottom

Tests/
└── LumoKitTests/               # XCTest; fixtures are generated, never committed
    ├── Fixtures.swift                 # builds .cube files and orientation-tagged JPEGs in a temp dir
    ├── AdjustmentControlTests.swift   # the nine controls' ranges, labels, and node mapping
    ├── AdjustInspectorTests.swift     # adjust-panel binding behaviour
    ├── AppViewModelTests.swift        # coordinator wiring — status, errors, sidebar refresh
    ├── CubeLUTTests.swift             # parser, domain handling, index ordering, intensity, round-trip
    ├── DeriveCoordinatorTests.swift   # derive lifecycle, scratch-until-saved, save
    ├── DeriveInvarianceTests.swift    # a derived LUT ignores develop settings (gated on local RAW/JPG)
    ├── DevelopInspectorTests.swift    # probing, seeding, capability gating (partly gated on local RAW)
    ├── EditDocumentTests.swift        # identity invariant, Codable round-trip, versioning
    ├── ExportCoordinatorTests.swift   # single + batch export, failure handling, collisions
    ├── ExportCutoverTests.swift       # the migration of both export paths onto the document
    ├── ExportNamingTests.swift        # `‹photo›_‹LUT name›` stems + collision handling
    ├── FakeRenderEngine.swift         # a non-GPU renderer for driving the view model in tests
    ├── HistogramTests.swift           # histogram tallies from rendered documents
    ├── ImageLoadingTests.swift        # EXIF orientation across load/thumbnail/export
    ├── ImageSourceTests.swift         # source-reproduction values (URL/Data, native extent)
    ├── KeyMonitorTests.swift          # the keyboard monitor's start/stop + event routing
    ├── LibraryScanTests.swift         # async folder scans, error surfacing, collection navigation
    ├── LUTFilterCacheTests.swift      # filter caching keyed by LUT + colour space
    ├── LUTIDTests.swift               # ID encoding, derived:// handling, determinism
    ├── PackageSettingsTests.swift     # pins the manifest: target names + Swift 6 language mode
    ├── PixelAssertions.swift          # shared helpers for perceptual pixel assertions
    ├── PreviewCostBenchmark.swift     # preview render-cost measurements (skipped without local assets)
    ├── PreviewCutoverTests.swift      # the migration of preview rendering onto the document
    ├── RAWCapabilitiesTests.swift     # per-file capability probing drives the develop panel
    ├── RAWDevelopSettingsTests.swift  # .neutral sets nothing; apply() honours is*Supported gates
    ├── RecipeExtractorTests.swift     # cube assembly, neighbour smoothing, working resolution
    ├── RenderEngineTests.swift        # engine evaluation at each scale (fake + real context)
    ├── RenderPipelineTests.swift      # document → filter-graph folding; identity skips filters
    ├── RenderStackTests.swift         # preview/export parity through the full stack
    ├── ThumbnailTests.swift           # embedded-preview thumbnails (no demosaic, no CIContext)
    └── WorkingSpaceTests.swift        # preview/export parity, LUT-interp ↔ output lockstep
```

`ContentView` and `LumoCommands` are the only `public` symbols — the executable needs exactly those
two and nothing else.

`docs/PHASE2_SPEC.md` is the implementation plan behind the non-destructive render pipeline and RAW
develop controls; `docs/CODE_REVIEW.md` records the standing findings from the last full review.

## 🏗 Architecture notes

- **The edit is a value.** [`EditDocument`](Sources/LumoKit/Models/EditDocument.swift) — RAW develop settings, ordered adjustment nodes, and a LUT reference — is `Codable`, `Sendable`, `Equatable`. An empty document renders the source untouched. That one invariant is what buys preview/export parity, and (once persistence lands) undo, presets, and per-photo edits.
- **One pipeline, two scales.** [`RenderPipeline`](Sources/LumoKit/Models/RenderPipeline.swift) folds a document into one lazy `CIImage`; the [`RenderEngine`](Sources/LumoKit/Models/RenderEngine.swift) actor evaluates that graph at preview or full scale. Preview and export call the same function and differ only in `RenderScale` — their agreement is structural, not a convention.
- **Core Image stays inside the engine.** `CIImage`, `CIFilter`, and `CIContext` are not `Sendable`; they never cross the module boundary. Only values do — `EditDocument`, `ImageSource`, `CubeLUT`, `WorkingSpace`, `RenderScale` — plus a `CGImage?` or `Data` on the way out. The whole package compiles in **Swift 6 language mode** with zero concurrency escape hatches, and `PackageSettingsTests` fails if that ever changes.
- **MVVM with coordinators.** [`AppViewModel`](Sources/LumoKit/ViewModels/AppViewModel.swift) holds the source, document, and collection state, and owns four collaborators: `LUTLibrary`, `ImageCollection`, [`ExportCoordinator`](Sources/LumoKit/ViewModels/ExportCoordinator.swift), and [`DeriveCoordinator`](Sources/LumoKit/ViewModels/DeriveCoordinator.swift). The coordinators report *what* happened through `onStatus`/`onError` closures; deciding how to present it stays with the view model. Views observe, and the menu bar talks to it via `NotificationCenter`.
- **Panels are a seam, not a dependency.** Every operation that needs a file dialog is split into a `perform…` core taking an explicit URL and a thin `…Dialog` wrapper that runs the panel. `NSOpenPanel`/`NSSavePanel` can't run headless, so this is what makes export and save testable at all.
- **One colour seam.** [`WorkingSpace`](Sources/LumoKit/Models/WorkingSpace.swift) is the single source of truth for both the LUT interpolation space and the output encoding space, so they cannot drift apart; every render and export site takes it, defaulting to sRGB. Cube data is laid out R-fastest → G → B, matching both the `.cube` spec and Core Image's expected ordering.
- **Images are rendered upright.** `CIRAWFilter` honors EXIF orientation; plain `CIImage(contentsOf:)` does not, so every non-RAW decode goes through oriented load options. Preview, filmstrip thumbnail, reported dimensions, and export all agree.
- **Work stays off the main actor.** Decoding, preview rasterization, folder scans, LUT parsing, export, and recipe derivation all run detached and publish results back to `@MainActor`; slider changes are debounced and each render cancels the one before it. Previews are capped at 1600×1200; thumbnails read the file's embedded preview without ever demosaicing a RAW; exports are always full resolution.
- **No third-party code.** Everything ships with the system: SwiftUI, Core Image, AppKit, PhotosUI, Swift Charts, ImageIO, Metal, simd.

---

## 📦 Preparing for the App Store

1. Drop a 1024×1024 source icon into [`Assets.xcassets/AppIcon.appiconset`](Sources/Lumo/Assets.xcassets/AppIcon.appiconset).
2. Set your **Bundle Identifier** and **Team** in the target's Signing & Capabilities.
3. Keep **App Sandbox** enabled (the included entitlements already grant user-selected file access + app-scope bookmarks).
4. **Product ▸ Archive ▸ Distribute App ▸ App Store Connect.**

---

## 📄 License & attribution

Lumo is released under the [MIT License](LICENSE) — free to use, modify, and distribute.

Lumo began as a fork of [LUTzy](https://github.com/tsvb/lutzy); the original project's copyright
and license terms are preserved in `LICENSE`, as [Fork & attribution](#fork--attribution)
describes.

---

<div align="center">
<sub>Built with SwiftUI · Core Image · Metal — and nothing else.</sub>
</div>
