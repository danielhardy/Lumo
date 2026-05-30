<div align="center">

# 🎨 LUTzy

### Color-grade RAW photos with `.cube` LUTs — and reverse-engineer a camera's look back *into* one.

A fast, native macOS app for applying 3D LUTs to RAW/DNG and standard images, with live side-by-side preview and a one-of-a-kind tool that **derives a LUT from a RAW + JPEG pair**.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Core%20Image-9cf)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![GPU](https://img.shields.io/badge/rendering-Metal--accelerated-success)

</div>

---

## What is LUTzy?

LUTzy is a focused color tool built entirely on Apple frameworks — **SwiftUI** for the interface, **Core Image** (Metal-backed) for every pixel operation, and **zero third-party dependencies**. It does three things exceptionally well:

1. **Opens your photos** — native RAW/DNG demosaicing plus all the usual formats.
2. **Grades them with `.cube` LUTs** — browse a whole folder of looks and preview them instantly on the GPU.
3. **Reverses the process** — point it at a RAW file *and* the camera's straight-out-of-camera JPEG, and it will **synthesize a `.cube` LUT** that turns the neutral RAW into that JPEG's look. Bottle your camera's color science (or a borrowed film simulation) and apply it to everything else.

> [!TIP]
> The headline trick lives in **[Derive a LUT from a JPG](#-derive-a-lut-from-a-jpg)**. If you've ever wanted to capture a camera's JPEG look as a reusable LUT, that's the section to read.

---

## ✨ Features

### Open anything
- **Native RAW/DNG** via Core Image's `CIRAWFilter` — proper demosaicing, not just the embedded preview.
- Supported RAW: `DNG`, `CR2`, `CR3`, `NEF`, `ARW`, `ORF`, `RAF`, `RW2`, `PEF`, `SRW`, `X3F`, `RAW`.
- Standard formats: `JPEG`, `PNG`, `TIFF`, `BMP`, `HEIC`.
- **Drag & drop** a single image *or* a whole folder onto the window.
- **Import from Photos** (up to 50 at once) or **import a folder** straight from the toolbar.

### Grade with LUTs
- Parses standard `.cube` 3D LUTs (`LUT_3D_SIZE`, `DOMAIN_MIN`/`MAX`) and applies them through `CIColorCubeWithColorSpace` — **fully GPU-accelerated** via Metal.
- **Sidebar library** scans your LUT folder recursively and groups looks by subfolder, with a live search field and a running count.
- **Folder access survives restarts** through App Sandbox security-scoped bookmarks — pick your LUT folder once.

### Compare like you mean it
- **Side-by-side** original vs. graded, or a single full-bleed view — toggle with **`V`**.
- **Hold `Space`** to flash back to the original in single view.
- **`←` / `→`** cycles through every LUT in your library with instant preview.

### Work in batches
- A **filmstrip** appears along the bottom when you load multiple images, with async-generated thumbnails.
- **`[` / `]`** step through the set; the selected LUT stays applied as you go.

### Export at full quality
- **16-bit TIFF**, **JPEG** (q 0.95), or **PNG** — always at full source resolution, never the downscaled preview.
- Output is auto-named `‹photo›_‹LUT name›.‹ext›`.

---

## 🔬 Derive a LUT from a JPG

This is what makes LUTzy unusual. Most apps *apply* LUTs; LUTzy can also **manufacture** one.

**The idea:** your camera shot a RAW and, at the same instant, rendered its own JPEG using the manufacturer's color science (or whatever film simulation / picture profile you had dialed in). That JPEG *is* a look. LUTzy compares the neutral RAW against that JPEG and bakes the difference into a portable `.cube` file you can apply to any other photo.

**Menu:** `File ▸ Derive LUT from JPG…` (**`⌘D`**) → pick the RAW, pick the JPEG, hit **Derive**.

```
  RAW ──► CIRAWFilter (neutral baseline) ─┐
                                          ├─► align ─► sample smooth regions ─► build 33³ cube ─► .cube
  JPEG ─► decode ─► edge mask ────────────┘                                         │
                                                                                    └─► Analysis report
```

Under the hood the extractor:

1. Renders the RAW through the **same** default `CIRAWFilter` pipeline LUTzy uses everywhere — so the derived LUT drops straight back into the normal apply path with no baseline mismatch.
2. Lanczos-scales the RAW render to the JPEG's resolution and finds the integer-pixel alignment by luma cross-correlation.
3. Builds an **edge mask** from the JPEG (so in-camera sharpening can't contaminate the color samples) and draws ~200k samples from smooth regions only.
4. Accumulates them into a **33³ color cube**, smooths any sparse cells from their neighbors, and anchors the rest to identity.

### The analysis report

Every derivation comes with a readout (rendered with Swift Charts) so you understand *what the look actually does*:

| Metric | Meaning |
|---|---|
| **Tone curve** | Per-channel R/G/B input→output mapping, plotted against the identity line |
| **Saturation** | Chroma ratio in smooth regions — `>1` more saturated, `<1` more muted |
| **Sharpening** | High-frequency energy ratio — **measured but deliberately *not* baked into the LUT** (a LUT can't sharpen; apply it separately if you want to match) |
| **Coverage** | % of cube cells filled by real samples vs. interpolated |
| **Samples** | How many smooth-region pixels survived the edge mask |
| **Camera** | Make / model and EXIF contrast, saturation, sharpness, and white-balance tags from the JPEG |

The result previews live on your current image immediately and stays a scratch LUT until you click **Save to LUT Folder…**, at which point it joins your sidebar library like any other `.cube`.

---

## ⌨️ Keyboard shortcuts

| Key | Action |
|---|---|
| `←` / `→` | Previous / next LUT |
| `Space` (hold) | Show original (single view) |
| `V` | Toggle side-by-side / single view |
| `[` / `]` | Previous / next image (when multiple are loaded) |
| `⌘O` | Open image |
| `⌘⇧I` | Import from Photos |
| `⌘⌥I` | Import folder |
| `⌘⇧L` | Choose LUT folder |
| `⌘D` | Derive LUT from JPG |
| `⌘S` | Export |

> Arrow/letter shortcuts are handled by a window-level `NSEvent` monitor (SwiftUI's `.onKeyPress` doesn't fire reliably inside a `NavigationSplitView`); `⌘`-shortcuts flow through the standard menu bar.

---

## 🚀 Build & run

LUTzy is a Swift Package — no `.xcodeproj` to manage.

**Quickest (CLI):**
```bash
swift run
```
Builds and launches the app for fast iteration. Note: the SwiftUI executable target runs without the bundled asset catalog or sandbox entitlements, so the app icon and security-scoped bookmark persistence won't be active in this mode.

**Recommended (Xcode) — full app behavior, icon, and App Sandbox:**
```bash
open Package.swift     # or: xed .
```
Then select the **LUTzy** scheme and **Run** (`⌘R`). For a sandboxed build, add the **App Sandbox** capability and point it at the included [`LUTzy.entitlements`](LUTzy/LUTzy.entitlements) (user-selected read/write + app-scope bookmarks).

**Requirements:** macOS **14.0+**, Swift **5.9+** (Xcode 15+).

---

## 🗂 Project structure

```
LUTzy/
├── LUTzyApp.swift              # @main App — window, default size, File-menu commands
├── Models/
│   ├── CubeLUT.swift           # .cube parser + writer → CIColorCube filter (also in-memory init)
│   ├── ImageProcessor.swift    # Singleton: RAW/standard load, preview, thumbnails, export (Metal CIContext)
│   ├── LUTLibrary.swift        # Scans LUT folder, groups by category, sandbox bookmark persistence
│   ├── ImageCollection.swift   # Multi-image set with async thumbnail generation
│   ├── RecipeExtractor.swift   # (RAW, JPG) → 3D LUT derivation pipeline
│   └── RecipeReport.swift      # Analysis data model (tone curve, ratios, EXIF camera info)
├── ViewModels/
│   └── AppViewModel.swift      # Central @MainActor state: image, LUT, preview, export, derive
├── Views/
│   ├── ContentView.swift       # Split-view layout, toolbar, status bar, key monitor, menu receivers
│   ├── LUTSidebar.swift        # Searchable, category-grouped LUT list
│   ├── PreviewView.swift       # Side-by-side / single canvas, drag-drop, badges
│   ├── FilmstripView.swift     # Horizontal thumbnail strip for batches
│   ├── RecipeExtractorSheet.swift  # "Derive LUT from JPG" modal (pickers, progress, report)
│   └── RecipeReportView.swift  # Analysis card — Swift Charts tone curve + stat badges
├── Assets.xcassets/            # App icon + accent color
└── LUTzy.entitlements          # App Sandbox + user-selected file access
```

## 🏗 Architecture notes

- **MVVM.** [`AppViewModel`](LUTzy/ViewModels/AppViewModel.swift) is the single source of truth and owns the `LUTLibrary` and `ImageCollection`; views observe it, and the menu bar talks to it via `NotificationCenter`.
- **Core Image end to end.** RAW demosaicing (`CIRAWFilter`), LUT application (`CIColorCubeWithColorSpace`), scaling (`CILanczosScaleTransform`), and all export encoding run through one Metal-backed `CIContext`.
- **Color pipeline is sRGB**, with cube data laid out R-fastest → G → B (matching both the `.cube` spec and Core Image's expected ordering).
- **Responsive by design.** Previews are capped at 1600×1200 and LUT application is cancellable; exports and recipe derivation run off the main actor with progress reporting. Exports are always full resolution.
- **No third-party code.** Everything ships with the system: SwiftUI, Core Image, AppKit, PhotosUI, Swift Charts, ImageIO, Metal, simd.

---

## 📦 Preparing for the App Store

1. Drop a 1024×1024 source icon into [`Assets.xcassets/AppIcon.appiconset`](LUTzy/Assets.xcassets/AppIcon.appiconset).
2. Set your **Bundle Identifier** and **Team** in the target's Signing & Capabilities.
3. Keep **App Sandbox** enabled (the included entitlements already grant user-selected file access + app-scope bookmarks).
4. **Product ▸ Archive ▸ Distribute App ▸ App Store Connect.**

---

<div align="center">
<sub>Built with SwiftUI · Core Image · Metal — and nothing else.</sub>
</div>
