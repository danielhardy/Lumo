# Canvas observation boundary

LUMO-112 moves pointer-frequency presentation state out of `AppViewModel`'s broad publisher.
`CanvasInteractionState` owns navigation (`fit`, `fill`, zoom, and focal-point pan) plus the
transient crop tool state. `AppViewModel` still owns the committed crop in `EditDocument`, undo
grouping, persistence, and render scheduling. `InspectorState` applies the same boundary to
inspector presentation and tab selection.

The view graph is intentionally split at the observation boundary:

| Interaction | Publisher | Affected SwiftUI subtree |
| --- | --- | --- |
| Pan, pinch/wheel zoom, fit/fill/reset | `CanvasInteractionState` | `PreviewView` and canvas toolbar controls |
| Crop-handle or crop-move draft | `CanvasInteractionState` | `PreviewView` / `CropOverlayView` |
| Inspector open/tab selection | `InspectorState` | inspector and inspector toolbar controls |
| Apply/cancel crop | `AppViewModel` document publisher at the commit boundary | editor surfaces as required |

The `CanvasObservationTests` regression asserts that representative canvas, crop-draft, and
inspector mutations emit from their narrow state objects without emitting
`AppViewModel.objectWillChange`. This is a structural invalidation check; model tests cannot
prove SwiftUI body counts or frame delivery.

## Repeatable Instruments capture

Use the same source, window size, backing-pixel size, Release build, and cold/warm condition for
both captures. Record hardware, OS, commit, source dimensions/format, RAW decoder/version when
applicable, viewport/backing pixels, and whether supporting work is enabled. Run these interactions
for at least 10 seconds each: wheel/pinch zoom, pan, crop-handle drag, keyboard fit/fill/reset,
source switch, and inspector tab switch.

In SwiftUI instrument, compare body evaluations for `SourceBrowserView`, `FilmstripView`,
`InfoInspectorView`, `PreviewView`, and `CropOverlayView`. In Time Profiler and Points of Interest,
record main-thread time, allocations, and the input-to-display/frame gap using the existing
`PointerInput`, `RenderStart`/`RenderEnd`, `GPUComplete`, and `DrawablePresented` signposts. Export
the before and after traces with the capture metadata above; do not treat the structural test as a
substitute for a hardware trace.

Automated verification for this boundary:

```sh
swift test --filter CanvasNavigationTests
swift test --filter CropWorkflowTests
swift test --filter ComparisonModeTests
```
