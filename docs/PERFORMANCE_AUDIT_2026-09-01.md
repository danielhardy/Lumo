# Performance evaluation — September 1, 2026

Evaluated commit `724ad99`. This evaluation left application code unchanged. Its ten findings are now tracked in LUMO-106 through LUMO-115, created in backlog at the user’s request. Existing tickets were left intact.

The largest opportunity is to make image processing independent of canvas interaction, then reuse developed pixels and unchanged processing stages. The current Metal surface is persistent, but its input is still a lazy processing graph. Persistent presentation alone does not make pan and zoom cheap. Lowering image quality further would obscure these architectural costs and would not fix the confirmed cache error.

## Evidence and measurement limits

Local hardware: Apple M1 Pro, 10 CPU cores, 16 GB RAM; macOS 26.6. Existing benchmarks were run in Release configuration. These are individual rendering measurements, not application input-to-display timings or comparisons against Lightroom/Photomator. There is no `realworldtest` RAW fixture in this checkout, so RAW-specific costs below are identified from code and require representative camera files for measurement.

| Existing benchmark | Measured result |
| --- | ---: |
| 6000×4000 generated PNG: rebuild source/pipeline, then rasterize | 198.9 ms/render |
| Same benchmark through RenderEngine with source reuse | 4.9 ms/render |
| Effects at 1600×1200, 30 ticks | p50 8.61 ms; p95 15.11 ms |
| Current tone curve at 1024×768 | 3.33 ms/tick |
| Historical 64³ tone-curve implementation | 5.90 ms/tick |

The approximately 40× source-reuse difference demonstrates why avoiding new source graphs matters. It does not predict a 40× improvement for the whole app. The PNG round-trip benchmark is not the shipping Metal display path and should not become a new optimization ticket: that display detour has already been removed.

A standalone probe in `/tmp`, linked against the current debug LumoKit objects, reproduced a cache bug through the production `makeCIImage` entry point. Source: 3000×2000 PNG; requested box: 2400×1600.

| Request order | Actual results | Required results |
| --- | --- | --- |
| Interactive → settled | 1500×1000 → 1500×1000 | 1500×1000 → 2400×1600 |
| Settled → interactive | 2400×1600 → 2400×1600 | 2400×1600 → 1500×1000 |

The preview-result cache reported zero entries/hits in this probe; the developed-source cache reported one miss and one hit. This confirms both the scale collision and which cache the production display path uses.

## Ticket index

| Finding | DG ticket | Priority | Prerequisites |
| --- | --- | --- | --- |
| 1 | [LUMO-106 — Correct developed-source cache identity for effective render resolution](../.dg/issues/LUMO-106.md) | high | None |
| 2 | [LUMO-107 — Separate completed GPU image rendering from canvas presentation](../.dg/issues/LUMO-107.md) | high | LUMO-114 |
| 3 | [LUMO-108 — Add crop-aware resolution planning and reusable zoom detail levels](../.dg/issues/LUMO-108.md) | high | LUMO-106, LUMO-107 |
| 4 | [LUMO-109 — Replace redundant open-time development with bounded source preparation](../.dg/issues/LUMO-109.md) | high | LUMO-111 |
| 5 | [LUMO-110 — Coalesce edit persistence and remove per-tick whole-catalog rewrites](../.dg/issues/LUMO-110.md) | high | None |
| 6 | [LUMO-111 — Reuse unchanged RAW output and expensive processing prefixes](../.dg/issues/LUMO-111.md) | high | LUMO-106, LUMO-114 |
| 7 | [LUMO-112 — Isolate canvas and crop interaction from broad SwiftUI observation](../.dg/issues/LUMO-112.md) | medium | LUMO-114 |
| 8 | [LUMO-113 — Prioritize visible edits over histogram, comparison, prefetch, and export work](../.dg/issues/LUMO-113.md) | medium | LUMO-107 |
| 9 | [LUMO-114 — Make performance telemetry cheap, bounded, and tied to actual presentation](../.dg/issues/LUMO-114.md) | medium | None |
| 10 | [LUMO-115 — Restore the full adjusted canvas when re-entering Crop](../.dg/issues/LUMO-115.md) | high | None |

All ten tickets are in backlog. Dependencies encode implementation prerequisites; LUMO-106 and LUMO-114 establish cache correctness and measurement foundations. LUMO-110 and LUMO-115 can proceed independently.

## DG tickets mapped to the audit findings

### 1. P1 — Correct developed-source cache identity for effective resolution

**Evidence:** [RenderCacheKey.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderCacheKey.swift:25) maps `.preview(size)` and `.interactive(size, budget)` to the same width/height bits. It ignores the interactive budget. [RenderScale.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderScale.swift:30) caps interactive output at 1.5 MP, while [RenderEngine.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderEngine.swift:543) uses that shared key for standard-image development.

**Impact:** A settled standard preview can remain permanently undersized, or an interactive preview can process 2.56× its intended pixels in the reproduced case. This affects accuracy and responsiveness, not just cache efficiency.

**Approach:** Key source stages by their effective pixel dimensions/scale and any policy that actually changes source pixels. Include budget-derived resolution; avoid distinguishing equivalent requests unnecessarily. Keep output-quality identity where it affects final-result policy.

**Acceptance:** Test both request orders above through `makeCIImage`, different frame budgets, and the transition back from interaction. Settled dimensions must match an uncached settled render; interactive dimensions must obey the budget regardless of cache history. Pixel comparisons must also match the corresponding uncached output.

### 2. P1 — Separate completed image rendering from canvas presentation

**Evidence:** [RenderEngine.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderEngine.swift:140) returns a graph from `makeCIImage`. [PreviewSurface.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Views/PreviewSurface.swift:210) calls `context.render` inside the `@MainActor` MTKView coordinator. Navigation transforms that graph and submits it again. The actor method finishing therefore does not mean image processing finished. GPU execution is asynchronous, but graph evaluation/encoding and drawable acquisition still occur on the UI path.

**Impact:** Expensive adjustments, first-use kernels, or source evaluation can delay input handling. Pan/zoom has no explicit guarantee of sampling already-completed image pixels; Core Image may reuse intermediates, but the application does not own that guarantee.

**Approach:** Render off the main actor into reusable GPU textures or IOSurfaces, then present completed resources with a small transform/compositing pass. Preserve revision ownership and retain the last valid frame. Connect latest-request scheduling to actual processing completion, rather than just graph construction. Define context/device/queue ownership explicitly; the engine currently has a separate context from its static presentation context despite comments describing one context.

**Fidelity:** Keep color management, alpha semantics, and adequate intermediate precision. Do not bake processing stages into RGBA8 merely to obtain a texture. Avoid CPU readback. Preserve strict Swift concurrency rather than adding unchecked sharing of mutable filters.

**Acceptance:** Warm pan/zoom over available pixels invokes no source development or adjustment evaluation. Record main-thread encoding time, GPU time, and drawable presentation separately. Target one refresh interval for the transform response on 60 Hz displays, with p95 input-to-present ≤33 ms. Verify color-managed texture output against the current reference renderer.

### 3. P1 — Add crop-aware resolution planning and a reusable resolution pyramid

**Evidence:** [AppViewModel.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/ViewModels/AppViewModel.swift:1276) derives target resolution from the whole uncropped source and continuously varying zoom. Cache dimensions are exact floating-point values. [RenderPipeline.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderPipeline.swift:105) crops after source downscaling. Pinch updates request interactive rendering even when a sharper settled image is already available.

**Impact:** Zoom/resize creates many distinct source-cache entries and evicts useful ones. Deep zoom requests high source resolution without an explicit visible-region strategy. Cropping to one quarter of the source width/height can leave only one quarter of the required linear detail before the surface enlarges it. At equal aspect ratio, a 1600×1200 source preview becomes a 400×300 crop displayed at 1600×1200.

**Approach:** Plan resolution from the committed crop, visible viewport, actual backing pixels, and native source bounds. Reuse the nearest adequate discrete resolution level, with hysteresis. Keep an existing sharper result during navigation rather than replacing it with an inferior interactive level. Add visible-region tiles and neighboring-tile prefetch for large/native-resolution views where profiling justifies it. Core Image already performs ROI optimization; measure its actual work before assuming every graph evaluates its full extent.

**Fidelity:** Tiles must preserve full-image coordinates, spatial-filter support outside tile boundaries, crop geometry, grain seed/phase, and vignette geometry. Do not change processing order by moving crop ahead of spatial effects. Full-quality visible tiles must be available for accurate detail inspection.

**Acceptance:** Small committed crops receive enough pixels for the viewport up to native resolution. Zooming between adjacent values does not repeatedly create source decoders. Repeated zoom/pan across cached regions is a presentation operation. Compare tile boundaries and crop results to the full-image reference with sharpening, clarity, dehaze, grain, and vignette enabled.

### 4. P1 — Replace open-time image development with source preparation and bounded loading

**Evidence:** [AppViewModel.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/ViewModels/AppViewModel.swift:695) starts an unstructured detached `ImageDecoder.load`, waits for it, then loads the edit record. [ImageDecoder.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/ImageDecoder.swift:113) accesses a neutral RAW filter's `outputImage`; the engine subsequently creates its own source graph. `sourceImage` is used as an availability flag rather than as the renderer's source. RAW capabilities instantiate another filter. Canceling the parent load does not cancel the detached operation.

**Impact:** First useful pixels wait on unnecessary source preparation; rapid navigation can leave obsolete loads running. The code accesses a full-resolution RAW output graph, although this audit does not claim every pixel is eagerly rasterized at that point.

**Approach:** Create a value-based source descriptor using oriented metadata and decoder geometry as appropriate. Load edit state concurrently with source preparation. Reuse a renderer-owned RAW session for dimensions, capabilities, and actual development. Bound navigation loading to active work plus the newest pending source. Cache/prefetch adjacent edited previews at idle priority.

**Fidelity:** Embedded camera JPEGs are not equivalent to the current edited RAW. Any optional placeholder must remain distinct from the authoritative color-managed preview and must not be used for histogram or detail assessment.

**Acceptance:** Opening does not request a neutral full-resolution RAW output solely to determine readiness/dimensions. Rapid navigation has bounded outstanding loads and never publishes the wrong source. Measure cold first-useful-pixel, cold settled-image, and warm revisits separately on 24 MP and 40–60 MP RAW plus standard images. Warm cached revisits should display within 100 ms.

### 5. P1 — Coalesce edit persistence and avoid rewriting the catalog per pointer tick

**Evidence:** [AppViewModel.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/ViewModels/AppViewModel.swift:1150) calls `saveActiveDocument` for each changed slider value. [queuePersistence](/Users/dhardy/Dev/Lumo/Sources/LumoKit/ViewModels/AppViewModel.swift:1950) chains every task behind its predecessor without coalescing. [EditDocumentStore.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/EditDocumentStore.swift:318) encodes all records, reads/validates the previous catalog, and atomically writes backup and primary on every save. Locator/bookmark creation also repeats.

**Impact:** Persistence work scales with pointer events × catalog size, even though rendering drops superseded events. The backlog consumes CPU/I/O and can delay a subsequent edit-store load or shutdown.

**Approach:** Keep live state immediate, with a bounded map of the latest dirty document per asset. Coalesce writes during gestures, flush on gesture end/source switch/termination, and periodically checkpoint long gestures. Cache unchanged locators. For larger catalogs, use per-record persistence or a transactional store rather than whole-catalog replacement.

**Acceptance:** A multi-second drag creates bounded outstanding work independent of event count. Its final value survives reopen, rapid source switches, undo/redo, and termination. Exercise write failures and interruption recovery. Benchmark 10, 1,000, and 10,000 edited-photo catalogs; retain the documented durability policy rather than silently deferring saves indefinitely.

### 6. P1 — Reuse unchanged RAW outputs and processing prefixes

**Evidence:** [RenderEngine.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderEngine.swift:549) sends every interactive RAW request through `InteractiveRAWFilterSession.output`, even for downstream light/color/LUT changes. That method restores all baseline values, reapplies settings, writes scale, and requests `outputImage` every time. [RenderPipeline.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderPipeline.swift:92) reconstructs the full downstream graph. The final preview cache belongs to the encoded `render` path, not `makeCIImage`.

**Impact:** Keeping the CIRAWFilter alive avoids construction but does not explicitly reuse unchanged output or completed upstream processing. RAW property writes may invalidate expensive decoder work; the exact cost must be measured with actual RAW files.

**Approach:** Memoize the RAW output by source revision, develop settings, and effective scale. Apply only changed decoder properties, including correct restoration of optional defaults. Introduce bounded caches at measured expensive stage boundaries, with downstream-only invalidation. In particular, changing LUT intensity or grain should reuse unchanged development and earlier spatial effects.

**Acceptance:** A light/color/LUT/grain drag with fixed develop settings does not reconfigure RAW or request a fresh RAW output per event. Cache hits must agree with fresh pipeline output, including optional-setting resets and source replacement. Profile cold/warm CPU, GPU, allocation, and memory behavior. Avoid indiscriminately materializing every node: that can defeat Core Image fusion and increase bandwidth.

### 7. P2 — Isolate canvas interaction state from the application observation graph

**Evidence:** [PreviewView.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Views/PreviewView.swift:6) and the surrounding editor observe the broad AppViewModel. Navigation and crop draft mutations are published there. `PreviewSurface` already isolates image publication, but not pointer-frequency navigation/document/draft updates.

**Approach:** Introduce narrowly observed canvas/crop state and inspector state. Let transform and handle movement update their own view subtree. Keep document history and persistence at clear commit/checkpoint boundaries. Use SwiftUI profiling to identify expensive invalidations rather than migrating frameworks solely on assumption.

**Acceptance:** Pan/crop-handle events do not reevaluate unrelated browser, filmstrip, or inspector bodies. Correlate view-body work with frame gaps. Preserve keyboard commands, selection, undo grouping, and accessibility.

### 8. P2 — Schedule supporting render work after actual presentation

**Evidence:** Histogram processing and exports use the same RenderEngine actor as display graph construction. [RenderEngine.histogram](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/RenderEngine.swift:341) lacks an entry cancellation check and performs synchronous bitmap rendering. [AppViewModel.publishPreview](/Users/dhardy/Dev/Lumo/Sources/LumoKit/ViewModels/AppViewModel.swift:1599) starts supporting work after graph publication, before actual presentation. Comparison baseline work is scheduled at open even when hidden.

**Approach:** Give visible edits priority over histograms, hidden comparison preparation, prefetch, and batch export. Check cancellation before expensive work and prevent obsolete supporting jobs from entering the actor. Define independent execution capacity for long non-preemptible export work, with GPU resource limits. Compute histograms from reusable rendered stages where the histogram contract permits it.

**Acceptance:** Dragging while exporting or opening Info does not wait behind avoidable obsolete work. Hidden comparison generates no unnecessary evaluated pixels. Histogram values retain their intended whole-image/crop and color-space semantics; do not silently replace them with a zoomed viewport histogram.

### 9. P2 — Make performance telemetry cheap, bounded, and representative

**Evidence:** [Observability.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/Observability.swift:85) repeatedly derives a trace token from `source.cacheFingerprint`. [ImageSource.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/ImageSource.swift:119) performs URL resource queries and `lstat`; pointer/render/GPU/display events repeat this work, including on the main actor. [LiveEditTelemetry.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Models/LiveEditTelemetry.swift:90) retains all samples indefinitely and reports requested rather than effective dimensions. Settled promotion allocates a new revision without registering an input sample, so final-frame completion is not fully represented. The existing “60 MP-class” coordinator benchmark uses a fake renderer and measures publication, not GPU presentation.

**Approach:** Capture a stable trace token for each source session and refresh file identity at explicit validated boundaries. Keep source-replacement correctness independent of logging. Use bounded sample retention. Record effective render/tile dimensions and connect final promotion to the originating user input. Add an actual Metal presentation benchmark plus a saved RAW capture matrix. Precompile legacy source-string kernels to Metal as a separately measured cold-start follow-up.

**Acceptance:** No filesystem metadata query or repeated digest generation is needed merely to emit a pointer/GPU/display event. Memory remains bounded over a 30-minute editing session. Reports include release-to-final-presentation latency and navigation gaps, and clearly distinguish fake orchestration timings from real pixels.

### 10. P1 correctness companion — Restore the full canvas when re-entering Crop

**Evidence:** [AppViewModel.beginCrop](/Users/dhardy/Dev/Lumo/Sources/LumoKit/ViewModels/AppViewModel.swift:1381) resets navigation and exposes the draft but does not request an uncropped image. [PreviewView.swift](/Users/dhardy/Dev/Lumo/Sources/LumoKit/Views/PreviewView.swift:103) continues using the committed cropped surface while its overlay uses full `sourceSize` coordinates.

**Impact:** After committing a crop, re-entering Crop draws a full-source-coordinate overlay over already-cropped pixels. Performance work must not make this incorrect geometry merely faster.

**Approach:** Retain/reuse the uncropped adjusted stage for crop editing and map the overlay to that stage. Commit/cancel switches composition without source redevelopment where cached source detail is adequate. Keep final crop-relative vignette/grain behavior explicit.

**Acceptance:** Commit → reopen → expand/reset/cancel works on landscape and oriented portrait images, including after zoom and undo/redo. Verify visible geometry, not only the stored normalized rectangle.

## Implementation sequence and quality gates

Start with tickets 1 and 9 to establish correct caches and trustworthy measurements, then implement 2/3/6 as the main rendering architecture work. Ticket 4 addresses first-image and navigation latency; ticket 5 removes unrelated work from editing. Tickets 7/8 complete interaction isolation and resource scheduling. Ticket 10 should accompany crop work.

Preserve the existing deterministic edit order, color management, native-resolution export, and grain determinism. Validate fine detail, high-contrast edges, skin tones, saturated/wide-gamut patches, transparency, crop edges, and tile boundaries. The same graph at different resolutions is not proof of pixel equivalence for nonlinear and spatial operations. If temporary lower-resolution feedback remains, it must reliably converge to the correct visible resolution and must never overwrite a better valid result during navigation.

For “instant,” measure p50/p95/p99 input-to-present, delivered FPS, worst frame gap, release-to-final-resolution, main-thread stalls, and memory over sustained use. Target ≤33 ms p95 for ordinary adjustments and canvas interaction at 60 Hz, ≤50 ms for RAW develop, and ≤200 ms to the settled image after release as initial acceptance goals, not claims already achieved. Do not accept a change solely because a graph-building benchmark became faster.

Apple's [CIImage documentation](https://developer.apple.com/documentation/coreimage/ciimage) explains that CIImage is a deferred recipe; its [Core Image optimization session](https://developer.apple.com/videos/play/wwdc2020/10008/) covers asynchronous render destinations and pipeline scheduling. These support separating graph creation, rendering, and display in the proposed design; application-specific gains still need measurement.

## Validation performed

- Focused navigation/coordinator/surface/cache tests: 27 executed, 1 opt-in benchmark skipped, 0 failures.
- Existing Release benchmarks: 3 executed, 0 failures. Raw logs: `/tmp/lumo-performance-bench.log`.
- Standalone cache reproduction: `/tmp/lumo-cache-probe.swift`, linked against current LumoKit objects, generated image data only; no application source edits.
- Additional crop/comparison/persistence tests: 15 executed, 0 failures. Raw log: `/tmp/lumo-performance-crop-tests.log`.
- No GUI Instruments capture or Lightroom/Photomator comparison was performed. RAW optimization effects and full input-to-display latency remain measurement tasks.
