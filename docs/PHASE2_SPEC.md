# LUTzy Phase 2 — non-destructive render pipeline + RAW develop

**Status:** design, not code. Steps 0–4 of the migration are done; the rest is unbuilt.

This is a distillation. The original draft ran 4,180 lines of multi-agent output that contradicted
itself across sections and spent a good fraction of its length arguing with earlier drafts about bugs
that never existed. Everything load-bearing is below; the original is in git history at `05ac1d6`.

**Baseline note:** the original was written against the pre-review codebase. Several of its premises
have since been fixed and are marked ✅ below — do not re-solve them.

---

## 1. What Phase 2 is for

LUTzy applies one LUT to one image and bakes the result. Phase 2 makes the edit a **value** instead of
a baked image, which buys four things at once:

1. **Preview/export parity becomes structural.** Today `renderPreview` and `export` are two code paths
   that merely agree. After: one `buildImage` call differing only by a scale value.
2. **RAW develop controls** — exposure, temperature, contrast, noise reduction — via `CIRAWFilter`'s
   native properties, which must be set *before* `outputImage` and so cannot be a post-hoc node.
3. **Undo, presets, and per-image edits for free** from a `Codable` document.
4. **One color seam** instead of four scattered `sRGB` literals plus two implicit sites.

---

## 2. Baseline — what is already true

| | |
|---|---|
| ✅ `LUTzyKit` library + thin `@main` executable, 95 XCTest cases, `swift test` in CI | Step 0 is **done** |
| ✅ Preview rasterization and decode run off the main actor; intensity slider debounced | the "full filter graph on the main thread" bug is **fixed** |
| ✅ LUT intensity ships today — `lutIntensity`, `CubeLUT.apply(to:intensity:)`, toolbar slider | the original called this "NEW behavior… exists nowhere". It exists. |
| ✅ EXIF orientation baked at load for every non-RAW decode | the original's "standard images have NO orientation baking" is stale |
| ✅ `AppViewModel` split into `ExportCoordinator` + `DeriveCoordinator` | the `[processor]`-capture hazard now lives in `ExportCoordinator` |
| ✅ `ImageProcessor.rawExtensions` internal; `developRAWNeutral` is the one neutral baseline | |
| ✅ Derive: cancellable, geometry-validated, capped at a 3000 px working resolution | |
| ✅ The value-state types exist (`EditDocument` and friends) — but nothing uses them yet | Step 2 is **done** |
| ✅ `RenderPipeline.buildImage` and `LUTFilterCache` exist — also unused | Step 3 is **done** |
| ✅ `actor RenderEngine` + `RenderEngining` exist, with a fake for tests — still unused | Step 4 is **done** |
| ❌ Nothing wired to the app; no RAW develop UI | the actual Phase 2 work |

**Still true and still worth fixing:** `ImageProcessor` is a non-`Sendable` `final class` singleton
holding a `CIContext`, captured into `Task.detached` in several places. Strict concurrency would reject it.

**Step 8's scope is now measured, not guessed.** Compiling `LUTzyKit` with
`-strict-concurrency=complete` under the macOS 26 SDK reports **one** remaining diagnostic:
`ImageProcessor.shared`. The whole Phase 2 stack — `EditDocument`, `RenderPipeline`, `LUTFilterCache`,
`RenderEngine` — is already clean, and `sending CGImage?` typechecks in Swift 5 language mode, so no
upcoming-feature flag is needed. Step 7 dissolves `ImageProcessor`; Step 8 should then be close to a
one-line change:

```
swiftc -typecheck -swift-version 5 -strict-concurrency=complete \
    -target arm64-apple-macosx14.0 $(find Sources/LUTzyKit -name '*.swift')
```

---

## 3. Architecture (binding)

Four layers, strict dependency direction:

```
EditDocument (value: Codable, Sendable, Equatable)   ← the look; serializable, undoable
        │  described by
        ▼
RenderPipeline.buildImage(...)        ← pure fn: EditDocument → ONE lazy CIImage
        │  evaluated by
        ▼
actor RenderEngine (owns the ONE CIContext)   ← rasterize at .preview or .full
        │
        ├── CGImage → @MainActor wraps NSImage   (preview)
        └── Data    → write(to:)                 (export)
```

`RecipeExtractor` sits **outside** this stack. It never imports `EditDocument`, never calls
`RenderEngine`, and keeps its own `CIContext` and its own sRGB sampling space.

### The types

```swift
struct EditDocument: Codable, Sendable, Equatable {
    var version: Int = 1                            // migrate explicitly as the schema grows
    var rawDevelop: RAWDevelopSettings = .neutral   // only meaningful for RAW sources
    var adjustments: [AdjustmentNode] = []          // ordered tone/color stages
    var lut: LUTSettings = .none                    // LUT by ID + intensity
}

/// nil = "leave CIRAWFilter at its decoder default", so .neutral is byte-identical
/// to today's developRAWNeutral output.
struct RAWDevelopSettings: Codable, Sendable, Equatable { /* exposure, neutralTemperature, … */ }

/// CLOSED enum, not [any AdjustmentNode] — see §4.1.
enum AdjustmentNode: Codable, Sendable, Equatable {
    case exposure(ev: Double)
    case colorControls(brightness: Double, contrast: Double, saturation: Double)
    case highlightShadow(highlights: Double, shadows: Double)
    case temperatureTint(temp: Double, tint: Double)
    case vibrance(amount: Double)
}

struct LUTSettings: Codable, Sendable, Equatable { var lutID: LUTID?; var intensity: Double = 1.0 }
struct LUTID: Codable, Sendable, Hashable { let raw: String }   // String, NOT UUID — see §4.3

/// How to REPRODUCE the source, so RAW can be re-developed per render.
/// A URL or Data, never a live CIImage: nothing non-Sendable enters app state.
struct ImageSource: Sendable, Equatable {
    enum Backing: Sendable, Equatable { case url(URL), data(Data) }   // .data covers Photos imports
    enum Kind: Sendable, Equatable { case raw, standard }
    let backing: Backing; let kind: Kind; let nativeExtent: CGSize
}

enum RenderScale: Sendable, Equatable { case preview(maxSize: CGSize), full }
enum WorkingSpace: String, Codable, Sendable { case sRGB, displayP3; static let current = WorkingSpace.sRGB }
```

`RenderPipeline.buildImage(source:document:lut:scale:space:) -> CIImage?` folds those into a single
lazy graph — source → RAW develop → ordered nodes → LUT-with-intensity — rasterizing **nothing**
in between. `actor RenderEngine` owns the only `CIContext` and evaluates it at one of two scales.

Preview downscales **early**: `CIRAWFilter.scaleFactor` before `outputImage` for RAW, a Lanczos step
right after load for standard images. Adjustment and LUT nodes then operate on ~1600×1200 px rather
than full extent.

---

## 4. The five decisions that matter

### 4.1 Adjustments are a closed enum, not protocol existentials

`[any AdjustmentNode]` cannot synthesize `Equatable`/`Codable` and needs a manual type-tag coder —
which undermines the value-state spine that earns undo and Swift 6 cleanliness in the first place. A
closed enum is equally ordered and composable, costs one case plus one switch arm to extend, and gets
the conformances free. For a small, known set of `CIFilter` wrappers this is strictly better.

### 4.2 RAW develop is not a node

`CIRAWFilter` must be rebuilt from the source and configured **before** `outputImage`; you cannot chain
develop onto an already-developed `CIImage`. So `rawDevelop` is a separate field consumed at the source
stage, and `ImageSource` carries a URL/Data rather than an image. This asymmetry is forced by the
framework, not a modelling preference.

### 4.3 The LUT is referenced by ID, and the ID is a `String`

`CubeLUT` holds a non-`Codable` float table; embedding it would make `EditDocument` non-`Codable` and
bloat every undo snapshot. So the document stores a `LUTID` resolved through a registry.

**The ID must be deterministic** — derived from `CubeLUT.id` (a file path). A random UUID would mint a
new ID on every `LUTLibrary.scan`, and since `saveDerivedLUT` triggers a rescan, persisted and undo
documents would silently stop resolving. Only in-memory derived LUTs get a synthetic ID.

### 4.4 One color seam, threaded rather than disciplined

There are **four** explicit `CGColorSpace.sRGB` literals today and **two implicit sites**:

| site | file | role |
|---|---|---|
| LUT interpolation | `CubeLUT.swift:152` | the space the cube interpolates in |
| Export encoding | `ImageProcessor.swift:259` | output encoding |
| Histogram render | `ImageProcessor.swift:188` | analysis only |
| Derive sampling | `RecipeExtractor.swift:101` | **stays pinned to sRGB, not `.current`** |
| *(was implicit)* | `ImageProcessor.renderPreview` `createCGImage` | **passed no colour space** — preview used the CIContext default while export forced sRGB |
| *(was implicit)* | `ImageProcessor.renderToNSImage` `createCGImage` | same |

✅ **Step 1 closed all six.** Every `CGColorSpace(name:)` literal in the module now lives in
`WorkingSpace.swift`; each site takes a `WorkingSpace` defaulting to `.current`.

The two implicit sites were a **latent preview/export mismatch** — byte-identical at sRGB, divergent
otherwise. Measured: reintroducing the bare `createCGImage` call moves the preview by up to **38/255**
against the export in Display P3, and by **0** in sRGB. That is exactly why a test asserting only
today's sRGB behaviour would not have caught it, and why the lockstep tests drive a non-default space
through both halves of the seam.

**Critical invariant:** LUT-interpolation space and output-encoding space must move in lockstep. They
are independent literals today that merely both happen to be sRGB. Threading one `WorkingSpace` value
through `buildImage` makes desync structurally impossible.

**Honest scope:** the seam governs LUT interpolation and output encoding, *not* source decode. A P3
JPEG is still funnelled to sRGB for interpolation, same as today. Don't oversell it.

**Derive is deliberately excluded.** A derived `.cube` is *fit* in the baseline-render space and later
*applied* in `WorkingSpace.current`; for it to be self-consistent, fit-space must equal apply-space.
Both are sRGB today. Never blindly thread `.current` into the derive sampler — its neutral RAW baseline
is itself an sRGB-default render. A P3 flip requires re-fitting derive **or** stamping the build space
onto the `CubeLUT`.

### 4.5 The GPU is the only isolation boundary

`actor RenderEngine` owns the single Metal `CIContext`. `CIImage`/`CIFilter`/`CIContext` are born and
die inside it. Only `Sendable` values cross in (`EditDocument`, `ImageSource`, `WorkingSpace`,
`RenderScale`, `LUTID`, `URL`/`Data`); a `sending CGImage?` or `Data` crosses out.

`CGImage` is **not** `Sendable` (verified, Swift 6.3) — use `-> sending CGImage?` (region-based
isolation), which keeps both the zero-`@unchecked` promise and the zero-copy benefit over returning bytes.

`ImageProcessor` dissolves: GPU duties move to the actor, the format vocabulary
(`rawExtensions`/`supportedExtensions`/`supportedTypes`) and `developRAWNeutral` stay as value-level statics.

The LUT filter cache lives on the **actor**, keyed by `LUTID` × color space — not on `CubeLUT`, which
stays an immutable `Sendable` value.

---

## 5. Invariants

- **Resolution independence.** Every `AdjustmentNode` must use normalized units. The current set
  (exposure, color controls, highlight/shadow, temp/tint, vibrance) is inherently scale-invariant. Any
  future pixel-sized node — grain, blur, sharpen — **must** express its radius normalized, or an
  early-downscaled preview and a full-res export diverge silently. This is the price of downscaling early.
- **RAW parity is tolerance-based by design.** `CIRAWFilter.scaleFactor` draft demosaic differs subtly
  from a full decode, so a scaled RAW preview is not byte-proof of the export. Test *wiring symmetry*
  (a knob moves both paths), not byte equality.
- **Derive baseline immunity.** `RecipeExtractor` must never receive `document.rawDevelop`. Enforced by
  construction (no `EditDocument` import; signatures take only URLs and options) plus a test that fails
  if the derive signature gains a develop parameter.
- **Empty document is identity.** An `EditDocument()` with no LUT must produce the source unchanged.

---

## 6. Migration

Each step builds, passes, and ships on its own. Introduce the spine *under* the old behavior, cut over
leaf by leaf, delete the old path last.

| Step | Work | Ship gate |
|---|---|---|
| ~~0~~ | ~~`LUTzyKit` split + test harness~~ | ✅ **done** — 95 tests, CI green |
| ~~1~~ | ~~`WorkingSpace`; route all six colour sites through it~~ | ✅ **done** — export, preview pixels and histogram byte-identical at sRGB; parity + lockstep tests added |
| ~~2~~ | ~~`EditDocument`, `RAWDevelopSettings`, `AdjustmentNode`, `LUTSettings`, `LUTID`, `ImageSource` — **defined but unused**~~ | ✅ **done** — plus `RenderScale`; 132 tests, nothing in the app references them, app launches unchanged |
| ~~3~~ | ~~`RenderPipeline.buildImage` + the actor-side LUT filter cache — **defined but unused**~~ | ✅ **done** — 162 tests; identity is pixel-exact, intensity endpoints exact, 21 mutations caught |
| ~~4~~ | ~~`actor RenderEngine` alongside the old path; a `RenderEngining` protocol so tests inject a fake~~ | ✅ **done** — 175 tests; preview/export parity asserted in both spaces; 12 mutations caught |
| 5 | Cut **preview** over. Keep computed `sourceImage`/`selectedLUT` shims so views compile | preview reflects develop + adjustments + intensity |
| 6 | Cut **export** over; delete `processedImage` | export honors develop at full res; parity test on one `EditDocument` |
| 7 | Move thumbnails (**both** `ImageCollection` sites — `generateThumbnails` *and* `addFromData`); dissolve `ImageProcessor` GPU duties | one `CIContext` **in the render stack** — `RecipeExtractor` keeps its own by design (§3), so the count to assert is 2, not 1 |
| 8 | Flip strict concurrency on | warning-clean build and test |
| 9 | Wire derive into the new state: register the derived LUT by ID, keep the scratch-file bookkeeping | derive-baseline invariance test |
| 10 | RAW develop + adjustments inspector, gated per-image on the real `is*Supported` flags | inspector drives live re-render |
| 11 | Per-image undo keyed by `Item.id`, plus an `EditDocumentStore` | ⌘Z scoped per image |
| 12 | *(deferred)* export descriptor, metadata/ICC | — |

Debounce **continuous edits only**. Open and filmstrip navigation must render immediately, or stepping
through a folder picks up latency for no reason.

---

## 7. Risks worth carrying

| Risk | Mitigation |
|---|---|
| **Random `LUTID`** → file-backed LUTs get new IDs on every scan, so saved documents silently lose their LUT | Deterministic `LUTID` from the path. Test that resolution survives a rescan. |
| **Fabricated `CIRAWFilter` API** copied from the original draft | Use the header-verified set in §9. Compile Step 2 early. |
| **Global undo stack** corrupts other images' edits on navigate-then-undo | Per-image, keyed by `Item.id` (not URL — nil for Photos imports) |
| **Photos `data:` imports** break if `ImageSource` is URL-only | `Backing.data(Data)`. Temp files misclassify RAW and need cleanup. |
| **`ExportFormat` promotion** loses `Identifiable` and its raw values | The toolbar `Picker` depends on both — keep them, update every reference in one commit |
| **Stale A/B cache** shows a pre-edit graded image during Space-hold | Encode `isShowingOriginal` into the render-request identity, or render an `intensity = 0` document |
| **Silent LUT failure** if the old "LUT application failed" branch is dropped | Validate once at parse/load and report, rather than per render |

---

## 8. Open questions — need sign-off

1. **Intensity blend space.** The dissolve mixes in the CIContext working space (≈ linear light), *not*
   in the cube's interpolation space. Measured on the current build, a to-black LUT over white reads
   255 / 225 / **188** / 137 / 0 at intensity 0 / .25 / .5 / .75 / 1 — a perceptual mix would read ~128
   at half. This is shipping behavior today, so changing it later is a visible look change for every
   sub-100% render. Decide deliberately.
2. **`kCIContextWorkingColorSpace` precision.** Setting `extendedLinearSRGB` + `RGBAh` changes
   intermediate precision for every render and needs a soft-clip before the 8-bit encoders (16-bit TIFF
   hides the out-of-gamut shifts). *Recommend: defer, CI default for v1.*
3. **Display P3.** Flipping `WorkingSpace.current` moves LUT-interp and output in lockstep, but derived
   LUTs were fit in sRGB and would mis-map. Prerequisite: a `buildSpace` on `CubeLUT`, or re-fit derive.
4. **New-image document policy.** Keep the current `EditDocument` across opens (A/B a look across a
   folder) or reset per open? *Recommend: keep.*
5. **"Original" for A/B.** Develop-applied-but-no-adjustments-no-LUT, or neutral RAW defaults?
   *Recommend: develop-applied.* Also decide whether side-by-side triggers on any non-neutral document
   or stays gated on "a LUT is set" as it is today.
6. **Adjustment list semantics.** Allow duplicate node cases, or one-of-each fixed slots?
   *Recommend: allow duplicates.*
7. **`CITemperatureAndTint` direction.** Still open, but no longer a guess — **measured** in Step 3 on
   a mid grey, with `neutral` pinned at D65 and only `targetNeutral` moving:

   | target | result | |
   |---|---|---|
   | 3200 K | (158, 121, 74) | warmer |
   | 6500 K | (128, 128, 128) | identity |
   | 9000 K | (119, 128, 144) | cooler |

   So raising Kelvin *cools*, inverting the Lightroom convention, exactly as suspected. Decide the
   mapping before shipping the node; identity at (6500, 0) is a safe seed either way.
   `testRaisingKelvinCoolsTheImage` pins today's direction, so flipping it later is a deliberate act
   with a failing test attached rather than a silent look change.
8. **Edit persistence across launches.** `EditDocument` is `Codable` to enable it; v1 in-memory only.
9. **RAW fixtures in CI.** Derive-invariance and RAW-parity tests need a license-clean small `.dng`+`.jpg`
   pair, else `XCTSkip`. Everything else in the suite generates its fixtures.

---

## 9. Verified facts — do not re-litigate

Checked against the SDK header and the real source. The original draft got several of these wrong in at
least one section, which is most of why it was so long.

**`CIRAWFilter`** (class is macOS 12+):
- The full `is*Supported` set **exists** — sharpness, moireReduction, contrast, detail, localToneMap,
  colorNoiseReduction, luminanceNoiseReduction, lensCorrection — and should gate its knob.
- `gamutMappingEnabled` is settable.
- EDR is a **single** knob, `extendedDynamicRangeAmount` (0...2), with no availability macro — callable
  **unguarded** on the macOS 14 target. There is no `isEDRModeEnabled` / `enableEDR`.
- Highlight recovery is the **only** knob needing `#available`. The header marks it `16_0`, which the
  Swift importer maps onto the renumbered **macOS 26** — `#available(macOS 26, *)` is what the
  compiler enforces, so that is what the code says. Every *other* property carries no per-property
  availability macro and dates from `CIRAWFilter` itself (`NS_CLASS_AVAILABLE(12_0, …)`), verified
  present as far back as the macOS 15.4 SDK.
- **SDK ≠ deployment target, and the SDK is a CI configuration choice.** Step 2 first shipped with CI
  on `macos-14` (Xcode 15.4, macOS 14.5 SDK), where the highlight-recovery properties are not in the
  imported interface *at all* — an availability check gates a call at runtime and cannot conjure a
  symbol the SDK never declared, so the reference failed to compile there while building clean on a
  current local Xcode. **Resolved by moving CI to `macos-26`** (which GitHub had deprecated `macos-14`
  in favour of anyway) while keeping the macOS 14 deployment target. That combination is the stricter
  one: the compiler now *refuses* newer API unless it is guarded. The cost is that the package
  requires Xcode 26+ to build; see `CLAUDE.md`. Step 10 is all new `CIRAWFilter` surface and depends
  on this arrangement.
- `isDustRemovalSupported` and `isBaselineExposureAvailable` **do not exist** — fabricated.

**This codebase:**
- `CubeLUT.id` is a `String` (file path, or `derived://…`). A `LUTID` wrapping `UUID` will not compile
  against it and would break resolution across rescans.
- `CGImage` is not `Sendable`; use `sending`.
- EXIF/ICC **cannot** be injected through `CIImageRepresentationOption` — that enum has no
  `kCGImageProperty*` channel. Metadata needs `CGImageDestination`, which is why it is Step 12.
  Note images are now baked upright at load, so a metadata path must force output `orientation = 1`
  rather than copying the source tag onto already-rotated pixels.
- `PreviewView` has no undefined symbol and no FIXME. The original draft argued with itself about this
  across four sections. It compiles; it always did.
