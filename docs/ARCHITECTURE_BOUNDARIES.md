# Lumo architecture boundaries

This document records the ownership boundaries for the application and render stack. It is
deliberately written before the coordinator extractions in LUMO-168 so future changes can be judged
against an explicit contract rather than against file size alone.

## State ownership

| Concern | Owner | Boundary exposed to the UI | Invariant |
| --- | --- | --- | --- |
| Source/import session | `AppViewModel` + `ImageCollection` | source actions and progress values | source identity and import progress are main-actor state; image bytes are retained only by the collection item that accepted them |
| Library scanning and projections | `ImageCollection` | `ImageCollection` observation plus pure `CollectionProjection` values | scanning mutates the collection; filtering, selection, and thumbnail-entry ordering are deterministic projections |
| Preview session | `PreviewCoordinator` + `PreviewSurface` | preview surface and `PreviewCoordinator` publication callbacks | a render completion must prove source/document identity before it can become visible |
| Editor document/history | `AppViewModel` | `document`, edit actions, and narrow canvas/inspector state objects | `EditDocument` is the single editable value; display state never becomes export state |
| Persistence | `EditPersistenceCoordinator` | pending-count/status passthroughs and flush/discard methods | snapshots are coalesced per asset and writes are serialized; cancellation never means that a dirty snapshot was discarded |
| Export | `ExportCoordinator` | export progress and panel-free request values | single and batch export use the same `RenderEngining` request funnel and never mutate the active document |
| Look workflows | `DeriveCoordinator`, `LookSaveCoordinator`, `LookPreviewCoordinator` | sheet-specific observable state | a sheet owns its transient task/result state; the editor only routes commands and status |

`AppViewModel` remains the application composition root. It owns navigation policy and connects
collaborators, but it should not own file I/O, collection projection algorithms, or render resource
lifetime. Its compatibility accessors (`selectedLUT`, `lutIntensity`, export request values, and
the persistence flush API) are intentional and are tested at the application boundary.

## Render ownership

`RenderPipeline` is a pure stage builder. It owns the ordered image stages:

```text
source/develop -> light -> color -> adjustments -> Look -> crop -> vignette -> grain
```

`RenderEngine` is the small actor façade (`RenderEngining`) that accepts `RenderRequest` values and
returns values or encoded bytes. `RenderEngineResources` owns the mutable GPU/Core Image lifecycle:
the `CIContext`, command queue/device, and cache instances. The engine retains only request-local
interactive RAW session state and the monitor that routes memory pressure to the resource holder.
No `CIImage`, `CIFilter`, `CIRAWFilter`, or `CIContext` crosses that actor boundary.

The split is intentionally not a second render path: the façade delegates stage construction to
`RenderPipeline` and resource/cache operations to `RenderEngineResources`. This keeps preview,
thumbnail, histogram, and export behavior on one request funnel while making stage and lifecycle
tests independent.

## View observation

Views that update at high frequency observe the narrowest state object available:

- `PreviewView` observes `PreviewSurface`, not a published image on `AppViewModel`.
- canvas gestures observe `CanvasInteractionState`.
- inspector chrome observes `AppViewModel.InspectorState`.
- library/grid/filmstrip views observe `ImageCollection`.
- export, derive, save-look, and settings sheets observe their dedicated coordinators.

The remaining inspector controls intentionally observe `AppViewModel` because their bindings mutate
the document and need command methods. A future editor-state extraction can migrate those bindings
without changing the source, persistence, preview, or export contracts above.

## Compatibility policy

Existing application-facing methods stay in place while collaborators are introduced. New code
should depend on the focused collaborator or protocol; compatibility methods should be thin routing
functions. Removing a compatibility API requires a repository-wide reference search and a test or
migration note in the same change.
