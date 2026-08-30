# Native RAW Photo Editor MVP — Implementation Plan

## Product Goal

Build a **very high-performance native macOS RAW photo editor** starting from the existing LUTzy codebase.

This is **not** intended to become LUTzy with more sliders. Treat LUTzy as a working technical foundation containing useful RAW decoding, Core Image/Metal rendering, LUT, thumbnail, histogram, metadata, Photos, and export code.

The resulting application should become its own cleanly architected product.

The MVP workflow is:

**Open/import a folder of photos → rapidly browse/select photos → edit nondestructively → optionally apply LUTs → copy edits between photos → export selected photos.**

The editing experience should cover essentially the global controls found in Lightroom's **Light, Color, and Effects** sections.

Performance is a primary product requirement, not a later optimization.

---

# 0. Rules for Working on This Repository

Do not begin by trying to understand the entire LUTzy repository.

For every task:

1. Search before reading.
2. Identify the smallest likely set of files involved.
3. Read no more than 5 files before forming an implementation hypothesis.
4. Make targeted changes once enough information is available.
5. Do not recursively explore unrelated architecture.
6. Never rewrite working image-processing code merely to make it cleaner.
7. Preserve useful LUTzy behavior until its replacement is working.
8. Run the narrowest relevant tests/build after each meaningful change.
9. Fix only failures related to the current work.
10. Prefer small coherent commits/milestones over a giant rewrite.

The goal is to evolve the working application while keeping it runnable.

---

# 1. First Task: Fork Cleanup and Product Rename

Do this before implementing features.

Assume this repository has just been forked from LUTzy.

Use `<APP_NAME>` as the new product name if the final name has not yet been decided.

## Rename

Rename application-facing and package-facing LUTzy references:

* `Sources/LUTzy` → `Sources/<APP_NAME>`
* `Sources/LUTzyKit` → `Sources/<APP_NAME>Kit`
* `Tests/LUTzyKitTests` → `Tests/<APP_NAME>KitTests`
* `LUTzyApp.swift` → `<APP_NAME>App.swift`
* `LUTzy.entitlements` → `<APP_NAME>.entitlements`
* Swift package target names
* module imports
* test module names
* schemes/product names where applicable
* user-facing strings
* bundle identifiers if present
* asset/app icon naming where appropriate

Do **not** remove the MIT attribution/license from the original LUTzy project.

Keep a notice in the repository acknowledging that the project began as a fork of LUTzy.

## Remove product-specific assumptions, not useful infrastructure

LUTs should remain a feature, but the app should no longer be architected around "the selected LUT" being the entire edit state.

Retain working implementations for:

* `CIRAWFilter` RAW decoding
* Core Image / Metal rendering
* `.cube` parsing
* `CIColorCubeWithColorSpace`
* LUT intensity blending
* asynchronous thumbnail generation
* folder scanning
* Photos import
* security-scoped bookmarks
* metadata reading
* histogram
* preview rendering
* full-resolution export
* render cancellation
* existing tests that still apply

LUTzy currently already provides native RAW decoding through `CIRAWFilter`, GPU LUT rendering, asynchronous thumbnails, full-resolution export, Photos import, histogram/metadata, and folder workflows. Preserve these capabilities while reorganizing them.

---

# 2. Establish the New Architecture Before Adding Sliders

Create a clear separation between:

1. Photo/library state
2. Nondestructive edit state
3. Rendering/image engine
4. UI
5. Export

The UI must never directly manipulate `CIFilter` objects.

The persisted edit model must not contain Core Image objects.

Core Image is an implementation detail of the rendering engine.

Target structure:

```text
Sources/
  <APP_NAME>/
    <APP_NAME>App.swift
    Assets.xcassets
    <APP_NAME>.entitlements

  <APP_NAME>Kit/
    App/
      AppState.swift
      NavigationState.swift

    Library/
      Models/
        PhotoAsset.swift
        PhotoCollection.swift
        PhotoRating.swift
      Services/
        PhotoLibrary.swift
        FolderScanner.swift
        ThumbnailService.swift

    Editing/
      Models/
        PhotoAdjustments.swift
        LightAdjustments.swift
        ColorAdjustments.swift
        EffectsAdjustments.swift
        LUTAdjustment.swift
        CropAdjustment.swift
      History/
        EditHistory.swift
      Presets/
        EditPreset.swift

    Imaging/
      RAW/
        RAWDecoder.swift
        AppleRAWDecoder.swift
      Rendering/
        PhotoRenderer.swift
        RenderRequest.swift
        RenderQuality.swift
        RenderCoordinator.swift
        PreviewCache.swift
      Pipeline/
        AdjustmentPipeline.swift
        LightPipeline.swift
        ColorPipeline.swift
        EffectsPipeline.swift
        LUTPipeline.swift
      CoreImage/
        CIContextProvider.swift

    Export/
      ExportService.swift
      ExportOptions.swift

    Views/
      Library/
      Editor/
      Inspector/
      Components/

    LUT/
      [existing LUT parser/library functionality]
```

This is a target organization, not permission for a giant file-moving exercise.

Move code incrementally and preserve builds.

---

# 3. Define the Nondestructive Edit Model

Every photo has immutable source data plus lightweight editable parameters.

Create a Codable, Equatable, Sendable model approximately like:

```swift
struct PhotoAdjustments: Codable, Equatable, Sendable {
    var light = LightAdjustments()
    var color = ColorAdjustments()
    var effects = EffectsAdjustments()
    var lut: LUTAdjustment?
    var crop = CropAdjustment()

    static let neutral = PhotoAdjustments()
}
```

Do not store rendered images inside this model.

Do not modify RAW originals.

## Light

Implement:

```text
Exposure
Contrast
Highlights
Shadows
Whites
Blacks
Tone Curve
```

Use ranges familiar to photographers, even if the internal implementation uses different normalized ranges.

Recommended UI:

```text
Exposure      -5.0 ... +5.0 EV
Contrast      -100 ... +100
Highlights    -100 ... +100
Shadows       -100 ... +100
Whites        -100 ... +100
Blacks        -100 ... +100
```

Lightroom's current Light panel uses Exposure, Contrast, Highlights, Shadows, Whites, Blacks, and Curve as its core tonal controls.

The implementation does **not** need to reproduce Adobe's algorithm mathematically.

It does need to have photographically sensible behavior.

Requirements:

* Exposure should behave approximately in EV.
* Highlights should predominantly affect upper tones.
* Shadows should predominantly affect lower tones.
* Whites should behave like a white-point/high-end adjustment.
* Blacks should behave like a black-point/low-end adjustment.
* Contrast should primarily alter tonal separation without immediately clipping endpoints.
* Controls should compose predictably.

---

# 4. Color Controls

Create:

```swift
struct ColorAdjustments {
    var temperature: Double
    var tint: Double

    var vibrance: Double
    var saturation: Double

    var mixer: ColorMixerAdjustments
    var grading: ColorGradingAdjustments
}
```

## MVP Color UI

Implement:

```text
White Balance
  As Shot
  Auto if technically practical
  Temperature
  Tint

Color
  Vibrance
  Saturation

Color Mixer / HSL
  Red
  Orange
  Yellow
  Green
  Aqua
  Blue
  Purple
  Magenta

For each:
  Hue
  Saturation
  Luminance

Color Grading
  Shadows
  Midtones
  Highlights

Each:
  Hue
  Saturation

Plus:
  Blending
  Balance
```

If HSL or Color Grading requires a custom Core Image kernel or Metal kernel for correct high-performance behavior, implement it behind the rendering abstraction.

Do not perform per-pixel Swift loops.

Temperature and tint for RAW files should use RAW-domain controls when practical rather than merely applying a post-render color cast.

---

# 5. Effects Controls

Implement the Lightroom-equivalent global effects:

```text
Texture
Clarity
Dehaze

Vignette
  Amount
  Midpoint
  Roundness
  Feather
  Highlights

Grain
  Amount
  Size
  Roughness
```

Adobe currently defines Texture, Clarity and Dehaze as the main Effects adjustments and provides Vignette and Grain controls with subordinate parameters.

## Important behavior distinctions

Texture, Clarity, and Dehaze must not simply be three differently scaled contrast sliders.

Target:

### Texture

Manipulates medium/high-frequency detail with minimal alteration to overall tone.

### Clarity

Primarily modifies local midtone contrast.

### Dehaze

Modifies local contrast/tone/color in a way that perceptually reduces or introduces haze.

### Grain

Should appear photographic rather than like uniform digital noise.

Grain should:

* be deterministic for the same image/edit state
* remain visually stable while sliders are manipulated
* not "dance" every time the image re-renders
* scale appropriately at export resolution

---

# 6. LUTs Become Part of the Edit Pipeline

Preserve LUTzy's existing `.cube` support.

A LUT should now be one nondestructive operation:

```swift
struct LUTAdjustment: Codable, Equatable, Sendable {
    var identifier: String
    var intensity: Double
}
```

UI:

```text
LOOK

None
[LUT browser]

Intensity  ─────●──── 65
```

Retain:

* LUT folder browsing
* `.cube` parser
* nested folders
* search
* GPU `CIColorCubeWithColorSpace` implementation
* intensity
* keyboard LUT navigation if practical

Do not make a LUT mandatory.

Neutral/no-LUT must be a first-class state.

## Pipeline order

Initially use a documented deterministic pipeline approximately:

```text
RAW decode / camera development
        ↓
white balance
        ↓
light/tone adjustments
        ↓
color adjustments
        ↓
texture / clarity / dehaze
        ↓
LUT
        ↓
vignette / grain
        ↓
crop / output transform
        ↓
display/export
```

If image-quality testing indicates another order is materially better, change it deliberately and document it.

Once released, pipeline ordering must become versioned because it affects reproducibility of old edits.

---

# 7. Build the Renderer as the Core Product

Create a renderer API with no UI dependencies.

Conceptually:

```swift
protocol PhotoRendering: Sendable {
    func render(_ request: RenderRequest) async throws -> RenderResult
}
```

A request should include:

```swift
struct RenderRequest {
    let asset: PhotoAsset
    let adjustments: PhotoAdjustments
    let targetSize: CGSize?
    let quality: RenderQuality
}
```

Quality should distinguish at least:

```text
thumbnail
interactive
preview
fullResolution
export
```

The same edit model must produce each quality level.

Do not create separate "preview edits" and "export edits."

---

# 8. Performance Is an MVP Requirement

The app should feel substantially faster than a traditional heavyweight RAW editor.

Architect for that from the beginning.

## Never block the main actor with:

* RAW decode
* thumbnail generation
* Core Image rendering
* image export
* folder scanning
* histogram generation
* metadata parsing
* cache I/O

Only UI state publication belongs on the main actor.

## Maintain one reusable rendering context

Do not recreate expensive `CIContext`/Metal infrastructure for every slider movement.

Create and reuse the appropriate Metal-backed Core Image context.

## Interactive rendering

During slider drag:

```text
adjustment changes
      ↓
cancel superseded render
      ↓
render viewport-sized image
      ↓
display immediately
```

When manipulation ends:

```text
slider released
      ↓
render high-quality preview
      ↓
replace interactive render
```

Do not full-resolution-render a 45–60 MP RAW for every slider event.

## Rendering priorities

Prioritize:

1. currently visible editor image
2. adjacent filmstrip thumbnails
3. visible grid thumbnails
4. background/precache work

Background work must yield to active editing.

## Cache

Implement bounded caches for:

* thumbnails
* RAW/developed preview intermediates where beneficial
* final preview renders

Cache keys must account for source identity, edit state/hash, render size, pipeline version, and other material rendering inputs.

Do not permit unbounded memory growth.

## Cancellation

If the user drags Exposure rapidly:

```text
0.1
0.2
0.3
0.4
0.5
```

the application should not queue five expensive renders.

Old requests should be cancelled/coalesced so the renderer converges on `0.5`.

---

# 9. Performance Targets

Instrument these instead of claiming that the app is "fast."

On a modern Apple Silicon Mac, aim for:

```text
App launch to useful UI:
< 1 second where realistic

Folder grid:
visible thumbnails begin appearing immediately

Photo-to-photo navigation:
embedded/cached preview effectively instantaneous

Cached editor photo switch:
target < 100 ms perceived response

Slider input latency:
target < 16 ms UI response

Interactive preview:
target >= 30 fps while manipulating common controls
stretch goal = 60 fps

No main-thread stalls:
>100 ms stalls should be treated as bugs

Memory:
bounded during long sessions and large folders
```

Rendering may refine after the initial visual response.

Perceived responsiveness matters more than eagerly completing unnecessary work.

Add signposts/instrumentation around:

* RAW load
* preview decode
* render graph
* thumbnail generation
* cache hit/miss
* photo switch
* export

---

# 10. Library / Import MVP

Do not build a giant Lightroom catalog yet.

The MVP should support opening/importing a folder containing:

* RAW
* JPEG
* HEIC
* TIFF
* other formats LUTzy already supports

Represent each source as `PhotoAsset`.

A photo needs:

```text
stable ID
URL/bookmark
filename
file type
dimensions
capture date
camera/lens metadata where available
rating
pick/reject state
adjustments
thumbnail state
```

## MVP library UI

Use a simple photographer workflow:

```text
Library

┌─────────────────────────────┐
│ Grid of photos              │
│                             │
│  [ ] [ ] [ ] [ ] [ ]       │
│  [ ] [ ] [ ] [ ] [ ]       │
│                             │
└─────────────────────────────┘
```

Support:

```text
← →        navigate
P          Pick
X          Reject
0          clear rating
1–5        star rating
Enter      edit selected photo
G          Grid
E          Edit
Space      temporary before/original where appropriate
```

Navigation and culling must work without waiting for full RAW development.

Use embedded RAW previews or thumbnails when advantageous.

---

# 11. Editor MVP

Use a Lightroom-like workflow but not a visual clone.

Target layout:

```text
┌──────────────┬──────────────────────────┬───────────────┐
│              │                          │ Histogram     │
│ Library      │                          │               │
│ / albums     │       PHOTO CANVAS       │ Light         │
│              │                          │ Color         │
│              │                          │ Effects       │
│              │                          │ LUT / Look    │
├──────────────┴──────────────────────────┴───────────────┤
│ Filmstrip                                                │
└──────────────────────────────────────────────────────────┘
```

Editing should be optimized around the photo, not around panels.

Requirements:

* large uninterrupted image canvas
* zoom/pan
* fit/fill
* before/after
* histogram
* collapsible inspector sections
* double-click slider value/name to reset
* reset panel
* reset all
* keyboard navigation between photos
* edits survive navigation
* no modal dialog for normal editing
* inspector remains responsive during rendering

---

# 12. Edit Persistence

Edits must survive application restart.

For MVP, prefer a simple local persistent representation rather than inventing a complex database.

Possible options:

* JSON sidecar/internal metadata store
* lightweight SQLite/SwiftData catalog

Choose based on the existing repository and minimum complexity.

Requirements:

* source RAW stays untouched
* edit state is tiny
* schema is versioned
* rendering pipeline version is stored
* missing/corrupt edit records fail safely
* future migrations are possible

Do not serialize Core Image implementation details.

---

# 13. History / Undo

Implement:

* undo
* redo
* reset individual adjustment
* reset panel
* reset photo
* copy edits
* paste edits

Slider dragging should produce **one undo operation**, not hundreds.

Example:

```text
mouseDown
  exposure = 0

drag
  .1 .2 .4 .6 .8

mouseUp
  exposure = .8
```

Undo should return directly to `0`.

---

# 14. Copy / Paste Edits

This is essential to the photographer workflow.

Support:

```text
Copy All Edits
Paste Edits
```

Then allow applying copied adjustments to multiple selected images.

Structure the implementation so selective copy can later support:

```text
☑ Light
☑ Color
☑ Effects
☐ Crop
☑ LUT
```

Full selective-copy UI can wait if necessary.

---

# 15. Export MVP

Retain and generalize LUTzy's full-resolution export path.

Support:

```text
JPEG
HEIF if straightforward
16-bit TIFF
PNG if already working
```

Options:

```text
full size
resize long edge
quality
color space
filename
destination
```

Export must always render from:

```text
original source
+
saved PhotoAdjustments
+
full-resolution pipeline
```

Never export the interactive preview bitmap.

Support:

```text
Export Current
Export Selected
```

Apple Photos export is desirable for MVP if straightforward through PhotoKit, but it should come **after** reliable file export.

Desired workflow:

```text
Select 24 Picks
↓
Export
↓
Apple Photos
↓
optional destination album
```

---

# 16. Histogram

Retain LUTzy's histogram functionality and adapt it to the new adjustment pipeline.

The histogram should represent the currently rendered edit, not merely the unedited RAW.

Histogram computation must not block slider responsiveness.

Prefer asynchronous/coalesced updates rather than recomputing unnecessarily for every transient slider value.

---

# 17. What Is Explicitly NOT MVP

Do not implement these unless required by foundational architecture:

```text
AI masking
brush masks
linear/radial masks
healing
generative remove
panorama merge
HDR merge
tethered capture
cloud sync
multi-user
face recognition
AI search
print books
plugins
video editing
mobile/iPad app
Photoshop round-trip
large Lightroom-compatible catalog import
camera tethering
```

Do not accidentally build V2 while trying to finish V1.

However, design `PhotoAdjustments` and the render pipeline so future **local adjustments/masks** can be added without rewriting every global adjustment.

---

# 18. Testing

Preserve LUTzy's existing test suite where applicable.

Add tests around the new engine, especially because photographic rendering can silently regress.

## Model tests

Test:

* Codable round trips
* neutral adjustment defaults
* edit-state equality
* copy/paste
* schema migration
* undo grouping

## Image pipeline tests

Generate deterministic test images and verify:

* neutral edit does not unexpectedly alter output
* Exposure +1 is brighter than Exposure 0
* Highlights predominantly modify upper luminance regions
* Shadows predominantly modify lower luminance regions
* Whites/Blacks affect appropriate ends
* saturation = -100 approaches monochrome
* LUT intensity 0 = no LUT
* LUT intensity 1 = full LUT
* deterministic grain
* full export uses source resolution

Avoid brittle pixel-perfect tests where framework/OS behavior can legitimately differ.

Use perceptual/numeric properties where appropriate.

---

# 19. Image-Quality Validation

Do not judge the pipeline only on whether sliders technically work.

Create a test set containing at least:

```text
highlights near clipping
deep shadows
underexposed RAW
high-ISO RAW
skin tones
green foliage
strong reds
blue sky
sunset gradient
mixed white balance
high dynamic range scene
low-contrast/hazy scene
```

For every major adjustment, compare visually with:

```text
Apple Photos
Lightroom
camera JPEG
our application
```

The goal is not pixel matching Lightroom.

The goal is:

> Would a photographer regard this control as predictable, useful, and visually high quality?

Tone/color quality is more important than matching Adobe slider math.

---

# 20. Development Milestones

Implement in this order.

## Milestone 0 — Clean Fork

Deliver:

* complete rename
* new target/module naming
* correct MIT attribution
* builds
* all applicable existing tests pass
* no functionality intentionally changed

Stop and commit.

---

## Milestone 1 — Engine Boundary

Deliver:

* `PhotoAsset`
* `PhotoAdjustments`
* `PhotoRenderer`
* `RenderRequest`
* `RenderQuality`
* reusable Core Image/Metal context
* existing LUT rendering moved behind pipeline abstraction
* neutral render path
* preview and export both use same model

Existing LUTzy UI may still drive the renderer.

Stop and commit.

---

## Milestone 2 — Light

Deliver all global Light controls:

* Exposure
* Contrast
* Highlights
* Shadows
* Whites
* Blacks
* Tone Curve

Add tests and image-quality samples.

Optimize interaction until common sliders are convincingly realtime.

Do not proceed if the editing interaction is sluggish.

Stop and commit.

---

## Milestone 3 — Color

Deliver:

* RAW white balance
* Temp
* Tint
* Vibrance
* Saturation
* HSL / Color Mixer
* Color Grading

Validate skin tones and highly saturated colors.

Stop and commit.

---

## Milestone 4 — Effects

Deliver:

* Texture
* Clarity
* Dehaze
* Vignette + advanced parameters
* Grain + size/roughness

Validate interactive performance.

Stop and commit.

---

## Milestone 5 — LUT Integration

Transform LUTzy's LUT functionality into a normal part of the new editor.

Deliver:

* LUT browser
* None
* LUT selection
* intensity
* LUT persisted in `PhotoAdjustments`
* LUT rendered at preview and full export resolution
* existing `.cube` compatibility retained

Stop and commit.

---

## Milestone 6 — New Editor UX

Replace LUTzy-centric main experience.

Deliver:

* image-centric editor
* Light / Color / Effects / LUT inspectors
* histogram
* zoom/pan
* before/after
* filmstrip
* keyboard photo navigation
* reset behaviors

Stop and commit.

---

## Milestone 7 — Culling / Library

Deliver:

* open folder
* fast grid
* async thumbnails
* ratings 0–5
* pick
* reject
* selected state
* filters for Picks / Rejected / rating
* rapid keyboard culling
* switch Grid ↔ Edit
* edits persist while moving between photos

Stop and commit.

---

## Milestone 8 — Persistence + Productivity

Deliver:

* persistent edits
* undo/redo
* copy edits
* paste edits
* multi-select paste
* simple presets if straightforward

Stop and commit.

---

## Milestone 9 — Export

Deliver:

* JPEG
* TIFF
* HEIF where supported cleanly
* PNG if retained
* full-resolution processing
* selected-image batch export
* quality/size options
* progress + cancellation
* optionally export directly to Apple Photos

Stop and commit.

---

## Milestone 10 — Performance Pass

Now test the application with:

```text
100 RAW photos
500 RAW photos
1,000+ RAW photos
24 MP files
40–50+ MP files
```

Profile with Instruments.

Find actual bottlenecks.

Do not optimize based on speculation.

Measure:

```text
main-thread stalls
photo-switch latency
thumbnail latency
interactive render duration
cache hit rate
memory growth
RAW decode duration
export throughput
```

Fix the highest-impact measured problems.

---

# 21. MVP Definition of Done

The MVP is complete when a user can:

1. Launch the application.
2. Open/import a folder containing hundreds of RAW files.
3. Immediately begin seeing thumbnails.
4. Navigate photos rapidly.
5. Pick/reject/rate photos.
6. Enter an Edit view.
7. Manipulate all global Light controls.
8. Manipulate all global Color controls.
9. Manipulate all global Effects controls.
10. Apply `.cube` LUTs and adjust their intensity.
11. See edits update interactively without UI stalls.
12. Navigate to another photo without losing edits.
13. Copy one photo's edits to another.
14. Undo/redo edits.
15. Close/reopen the application without losing edit state.
16. Filter to selected/picked photos.
17. Export those photos at full source quality/resolution.
18. Optionally send final exports directly to Apple Photos.

The experience should feel:

**native, immediate, simple, photographic, and substantially lighter than Lightroom.**

The goal is not feature parity with Lightroom.

The MVP wins if this workflow:

**shoot → open → cull → edit → copy edits → select → export**

is exceptionally fast and enjoyable.

---

# 22. Architectural Principle for Future Masking

Do not build masking for MVP.

But all global adjustments should eventually be usable as local adjustments.

Architect the pipeline conceptually so today's:

```text
PhotoAdjustments
    ↓
AdjustmentPipeline
```

can later become:

```text
PhotoAdjustments
    ↓
Global AdjustmentPipeline
    ↓
LocalAdjustment[]
       ├── mask
       └── adjustment subset
    ↓
output
```

Do not hard-code every adjustment directly into a monolithic SwiftUI ViewModel.

That will make future:

```text
Subject
Sky
Person
Brush
Linear Gradient
Radial Gradient
Luminance Range
Color Range
```

possible without replacing the image engine.

---

# 23. Most Important Engineering Principle

Do **not** rebuild image technology that Apple already provides.

Prefer, in order:

1. `CIRAWFilter`
2. existing Core Image filters
3. Core Image kernels / Metal where needed
4. custom image-processing algorithms only where the product requires behavior Apple's frameworks cannot provide

No CPU pixel loops in Swift for interactive image processing.

The application should remain overwhelmingly:

**Swift + SwiftUI/AppKit where appropriate + Core Image + Metal + Apple frameworks.**

Avoid third-party dependencies unless they solve a genuinely difficult problem that Apple frameworks cannot solve cleanly.

---

# 24. First Action

Begin with **Milestone 0 only**.

Inspect the current `Package.swift`, `Sources/LUTzy`, `Sources/LUTzyKit`, test target, entitlements, and user-visible identifiers.

Create a concrete rename map.

Then perform the rename while preserving a compiling and tested application.

Do not start implementing the new editor until the renamed fork builds and the existing relevant test suite passes.
