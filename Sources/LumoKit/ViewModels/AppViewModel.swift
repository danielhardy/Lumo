import Foundation
import CoreImage
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Central state for the Lumo app.
@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Published state

    @Published var sourceImage: CIImage?
    @Published var sourceName: String = ""
    @Published var sourceSize: CGSize = .zero
    @Published var sourceURL: URL?

    /// **The look, as a value.** Phase 2's spine: everything the user has chosen lives here, and the
    /// preview is rebuilt from it rather than from a baked image (`docs/PHASE2_SPEC.md` §3).
    ///
    /// Stored in a per-photo session keyed by stable source identity. Navigation restores the active
    /// photo's Light, other edits, and history without carrying them onto a different frame.
    @Published private(set) var document = EditDocument()

    /// How to reproduce the open image. Held instead of a decoded `CIImage` because a RAW has to be
    /// re-developed to honour `document.rawDevelop` (§4.2).
    private var imageSource: ImageSource?

    /// What the open image's RAW decoder can do, and where its own defaults sit. `nil` for a
    /// standard image, which has no develop stage at all — **and also `nil` while the probe is still
    /// running on a RAW**, which is why the panel switches on `developPanelState` rather than on
    /// this. See that property.
    ///
    /// Probed once per open rather than per render: the probe builds a `CIRAWFilter`, which measures
    /// ~25 ms on a 30 MB DNG. Not memoized across images — one entry would save that on returning to
    /// an image, at the cost of another cache whose invalidation nobody will remember.
    @Published private(set) var rawCapabilities: RAWCapabilities?

    /// What the develop panel should be showing right now. **Three states, not two.**
    ///
    /// `rawCapabilities` is `nil` in two situations that mean opposite things, and the panel used to
    /// treat them as one. `refreshCapabilities()` clears it **synchronously** on every open and
    /// refills it 25–170 ms later, so a RAW opened with the Develop tab already showing spent the
    /// whole probe reading "No develop stage — Develop controls come from the RAW decoder. This image
    /// is already rendered." That is a false statement about the file, and because `inspectorTab` is
    /// not reset on open it was shown again on every ←/→ step through a folder of RAWs.
    ///
    /// Deriving the state here rather than in the view is what makes it testable: this repo has no
    /// SwiftUI view tests, so a distinction that lives only in a `ViewBuilder` cannot be asserted.
    /// `DevelopInspectorView` is a `switch` over this value and nothing else.
    ///
    /// This — rather than a widened `imageSource` — is the whole of what the panel needs from the
    /// source: not the backing bytes, not the native extent, only whether a develop stage exists at
    /// all. See `sourceIsRAW` for the widening that does happen, and why it is a `Bool`.
    var developPanelState: DevelopPanelState {
        DevelopPanelState(sourceIsRAW: sourceIsRAW, capabilities: rawCapabilities)
    }

    /// Whether the open image goes through the RAW decoder at all.
    ///
    /// **Widened from `private` deliberately, and narrowly.** `imageSource` itself stays `private`:
    /// the develop panel has no business with the backing bytes or the native extent, and the one
    /// fact it needs — is there a decode stage that could offer develop controls — is a `Bool`.
    /// Publishing the `Bool` instead of the struct keeps the reason for the widening legible and
    /// stops anything else reaching through it. It is also the input the state mapping is tested
    /// against directly.
    ///
    /// Not `@Published`: it only ever changes inside `load()`, which writes several `@Published`
    /// properties in the same main-actor turn (`sourceImage` among them), so any view observing this
    /// view model is already being invalidated when it moves.
    var sourceIsRAW: Bool { imageSource?.kind == .raw }

    /// The three states of the develop panel. See `AppViewModel.developPanelState`.
    enum DevelopPanelState: Equatable, Sendable {
        /// Not a RAW (or nothing open): there is no develop stage to offer, and saying so is honest.
        case noDevelopStage
        /// A RAW whose capability probe has not landed yet. The controls are coming, so the panel
        /// must not claim there are none.
        case probing
        /// A RAW, probed. The panel draws `capabilities.availableControls`.
        case ready(RAWCapabilities)

        /// **The mapping, in one place, as a pure function of two inputs.** Written as an
        /// initializer rather than inlined into the computed property so the whole table — two
        /// inputs, three outcomes — can be asserted on any machine, including CI, which has no RAW
        /// to open (`DevelopInspectorTests.testThePanelStateMappingCoversAllThreeStates`).
        init(sourceIsRAW: Bool, capabilities: RAWCapabilities?) {
            if let capabilities {
                self = .ready(capabilities)
            } else {
                self = sourceIsRAW ? .probing : .noDevelopStage
            }
        }
    }

    private var capabilitiesTask: Task<Void, Never>?

    private var editSessions: [PhotoAssetID: PhotoEditSession] = [:]
    private var activeAssetID: PhotoAssetID?
    private var activeHistory = EditHistory()

    /// Source generation prevents delayed work from a previous navigation selection from publishing
    /// into the new image, even if the source values happen to compare equal.
    private var sourceRevision: UInt64 = 0
    /// Document generation guards the side-by-side baseline, whose request is managed separately
    /// from the primary visible render.
    private var documentRevision: UInt64 = 0
    private var isPreviewInteractionActive = false

    /// Whether any call since the last fired render changed `rawDevelop`.
    ///
    /// A coalesced burst of edits accumulates this flag while the preview coordinator keeps only the
    /// newest visible request. A baseline is released after that settled visible request, so an
    /// earlier develop edit in the burst is not lost when a later tick supersedes its value.
    private var pendingDevelopChange = false

    /// LUTs a document can reference that no folder scan produces — a freshly derived LUT, and the
    /// file it becomes once saved. See `DerivedLUTRegistry`; this is the Step 9 replacement for the
    /// single `scratchLUT` slot that stood here.
    private var derivedRegistry = DerivedLUTRegistry()

    /// **Shim.** The document stores a `LUTID`; views still want the LUT. Resolution is deliberately
    /// a fresh lookup rather than a cached object — `LUTID` is a file path precisely so a rescan
    /// cannot break it (§4.3).
    var selectedLUT: CubeLUT? { resolvedLUT(document.lut.lutID) }

    /// **Shim.** Reads through to the document so the toolbar slider keeps working unchanged.
    var lutIntensity: Double { document.lut.intensity }

    /// The document-level identity used by the Look inspector's selection binding. This remains
    /// separate from `selectedLUT`: an unresolved reference must not look like the explicit None
    /// choice in the browser.
    var selectedLookID: LUTID? { document.lut.lutID }

    /// True only for the explicit no-look state. A missing file keeps its stored ID and therefore
    /// stays visibly distinct from None until the user chooses to clear it.
    var isLookNoneSelected: Bool { document.lut.lutID == nil }

    /// Whether the Look stage has state worth resetting, including an unresolved stored reference
    /// and an intensity changed while no LUT was selected.
    var hasLookAdjustments: Bool { document.lut != .none }

    /// A missing LUT never prevents the source image from rendering. Keep the warning separate from
    /// the transient image status so the stored `LUTID` remains visible to callers and recoverable.
    @Published private(set) var lutResolutionStatus: String?

    /// Whether the A/B comparison — the split view and the Space-hold — has anything to show.
    ///
    /// **Not `selectedLUT != nil`**, which is what this was until Step 10b. That was defensible while
    /// a LUT was the only thing that could change the picture; the Adjust panel made it wrong, and an
    /// image with exposure pushed two stops and no LUT selected had a dead V key and a dead Space bar.
    /// `docs/PHASE2_SPEC.md` §8.5 recorded this as open.
    ///
    /// **Not `document != document.originalForComparison` either**, which is what Step 10b first
    /// reached for: compare the document against its own baseline rather than enumerate the
    /// look-bearing fields, and the rule "stays correct the next time the document grows a field."
    /// That reasoning is wrong for a LUT at 0% intensity — `LUTSettings.isIdentity` treats it as
    /// contributing nothing, but the plain `!=` sees `lutID` still set and calls the document
    /// non-neutral, so the gate opened a split view of two pixel-identical halves. Exactness beat the
    /// "survives a new field" property. The cost is real: the next look-bearing field added to
    /// `EditDocument` must be added to this expression by hand, or this comment starts lying the same
    /// way the old one did.
    ///
    /// A **develop-only** edit correctly reads `false` — `originalForComparison` keeps `rawDevelop`
    /// and strips Light, Color, adjustments, and the LUT, so both halves would render the same
    /// picture.
    ///
    /// `adjustments.isEmpty` would have been a sound stand-in for "no adjustment is active" only
    /// because the array is sparse — `AdjustmentControl.setting(_:in:)` never stores an identity node, a
    /// claim `AdjustmentControlTests` pins. `adjustments.allSatisfy(\.isIdentity)` needs no such
    /// precondition: a stray identity node reads exactly the same as no node at all, so it is written
    /// this exact way, rather than the cheaper `isEmpty`, for the same exactness reason as the
    /// paragraph above — it stays correct even if the sparse invariant is ever violated, which matters
    /// once Step 11's undo path can restore a document that arrived by decoding rather than by a
    /// slider write.
    var isComparisonAvailable: Bool {
        !document.light.isIdentity ||
            !document.color.isIdentity ||
            !document.effects.isIdentity ||
            !document.adjustments.allSatisfy(\.isIdentity) || !document.lut.isIdentity
    }

    @Published var isShowingOriginal: Bool = false
    @Published var isSideBySide: Bool = true

    /// The visible render is owned by these surfaces, not published image values on this model.
    let previewSurface = PreviewSurface()
    let originalPreviewSurface = PreviewSurface()

    /// Inspector visibility. Computing the histogram is gated on this — plus on the Info tab being
    /// the one on screen — so we don't tally pixels for a panel nobody's looking at.
    @Published var isInspectorPresented: Bool = false {
        didSet { if isInspectorPresented { updateHistogram() } }
    }

    /// Which panel of the inspector is showing.
    ///
    /// The histogram lives on `.info` only, so this gates it exactly as `isInspectorPresented` does:
    /// an open inspector showing Develop is as much "a panel nobody's looking at" as a closed one,
    /// and without this every settled render of a develop drag would tally an off-screen histogram.
    /// Switching **back** recomputes, or the panel would return blank (or stale) after a detour
    /// through Develop.
    @Published var inspectorTab: InspectorTab = .info {
        didSet { if inspectorTab == .info { updateHistogram() } }
    }

    enum InspectorTab: String, CaseIterable, Sendable {
        case info, light, develop, adjust
        case effects
        case look
        var title: String {
            switch self {
            case .info: return "Info"
            case .light: return "Light"
            case .develop: return "Develop"
            case .adjust: return "Adjust"
            case .effects: return "Effects"
            case .look: return "Look"
            }
        }
    }
    /// Source-folder file browser panel visibility.
    @Published var isSourceBrowserPresented: Bool = false
    /// Whether the source collection is being browsed as the virtualized library grid.
    @Published var isLibraryGridPresented: Bool = false
    /// EXIF/TIFF/GPS metadata of the loaded image, read at load time.
    @Published var metadata: ImageMetadata = ImageMetadata()
    /// Histogram of the currently displayed image (graded result, or original
    /// while comparing). `nil` until computed / when no image is loaded.
    @Published var histogram: HistogramData?
    private var histogramTask: Task<Void, Never>?

    @Published var isLoading: Bool = false
    @Published var statusMessage: String = "Open an image to get started"

    /// Non-nil when a hard failure should be surfaced as a dismissible alert.
    /// Bound to an `.alert` in ContentView; cleared when the user dismisses it.
    @Published var errorMessage: String?

    @Published var isPhotosPickerPresented: Bool = false

    // MARK: - Owned state

    let library = LUTLibrary()
    let workScheduler: ImageWorkScheduler
    let collection: ImageCollection
    /// Writing images to disk — the single export, the batch run, and naming.
    /// Shares this view model's engine, so an export renders through the same funnel the preview does.
    let export: ExportCoordinator
    /// The "Derive LUT from JPG" flow and its scratch-until-saved result.
    let derive = DeriveCoordinator()

    // Convenience passthroughs so views and the menu don't have to know which
    // collaborator owns a given piece of state.
    var isExporting: Bool { export.isExporting }
    var exportFormat: ExportFormat {
        get { export.format }
        set { export.format = newValue }
    }

    /// The renderer. An `any RenderEngining` rather than the concrete actor so a test can drive the
    /// preview flow without a GPU — the reason Step 4 introduced the protocol.
    private let engine: any RenderEngining
    private let previewCoordinator: PreviewCoordinator
    private var loadTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var originalPreviewTask: Task<Void, Never>?
    private var previewDebounceTask: Task<Void, Never>?
    private var cancellables: [AnyCancellable] = []

    // MARK: - Init

    init(engine: any RenderEngining = RenderEngine.shared) {
        var interval = LumoSignpostInterval(.launch, context: .unknown)
        defer { interval.end() }

        self.engine = engine
        self.workScheduler = ImageWorkScheduler()
        self.collection = ImageCollection(scheduler: workScheduler)
        self.export = ExportCoordinator(engine: engine)
        self.previewCoordinator = PreviewCoordinator(engine: engine)

        // Forward nested ObservableObject changes so SwiftUI views update.
        for child in [
            library.objectWillChange.eraseToAnyPublisher(),
            collection.objectWillChange.eraseToAnyPublisher(),
            export.objectWillChange.eraseToAnyPublisher(),
            derive.objectWillChange.eraseToAnyPublisher(),
        ] {
            cancellables.append(child.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            })
        }

        previewCoordinator.onPublication = { [weak self] publication in
            self?.publishPreview(publication)
        }
        previewCoordinator.onFailure = { [weak self] request in
            guard request.quality == .preview else { return }
            self?.statusMessage = "Could not render \(self?.sourceName ?? "image")"
        }

        wireCoordinators()
        library.restoreFolder()

        // Restore a previously-chosen source folder and open its first image.
        // Both the LUT scan above and this one run asynchronously, so the
        // window paints immediately and fills in as the scans land.
        if collection.restoreSourceFolder() {
            isSourceBrowserPresented = true
            isLibraryGridPresented = true
            collection.beginThumbnailDemand()
            openFirstImageWhenScanned()
        }
    }

    /// Point the coordinators' status/error output at this view model, which
    /// owns the status bar and the alert. They report *what* happened; deciding
    /// how to show it stays here.
    private func wireCoordinators() {
        // A rescan can mean the bytes behind an unchanged `LUTID` have changed — a path is the
        // identity, so a `.cube` replaced in place keeps it. Drop the engine's cube filters rather
        // than go on serving the old cube. Wired here, before `restoreFolder()` runs below, so the
        // launch scan is covered too.
        library.onScanned = { [weak self] in
            guard let self else { return }
            self.refreshLUTResolutionStatus()
            guard self.sourceImage != nil else {
                Task { await self.engine.invalidateLUTCache() }
                return
            }
            // A render submitted before the asynchronous scan may have been safely ungraded. Flush
            // first, then submit again, so an old cached cube cannot win the race with publication.
            let engine = self.engine
            Task { [weak self] in
                await engine.invalidateLUTCache()
                guard let self, self.sourceImage != nil else { return }
                self.schedulePreview()
            }
        }

        export.onStatus = { [weak self] in self?.statusMessage = $0 }
        export.onError = { [weak self] in self?.presentError($0) }

        derive.onStatus = { [weak self] in self?.statusMessage = $0 }
        derive.onError = { [weak self] in self?.presentError($0) }
        derive.onDerived = { [weak self] lut in
            // Preview the new look immediately, if there's something to see.
            guard let self, self.sourceImage != nil else { return }
            self.selectLUT(lut)
        }
        derive.libraryFolder = { [weak self] in self?.library.folderURL }
        derive.onSaved = { [weak self] destination in
            guard let self else { return }
            self.adoptSavedLUT(at: destination)
            // Re-scan so the new entry appears in the sidebar.
            guard let folder = self.library.folderURL else { return }
            self.library.scan(folder)
        }
    }

    /// Follow a derived LUT from memory onto disk.
    ///
    /// Saving is the moment a derived LUT becomes durable, so it is the moment its reference should
    /// become durable too. A `derived://` ID resolves only through the registry and cannot survive a
    /// relaunch; the path the user just chose is what a fresh launch would resolve and what the next
    /// library scan will hold. So the document is re-pointed at it.
    ///
    /// **The saved LUT is re-parsed from the file rather than aliased from memory.** `cubeFileContents`
    /// writes `%.6f`, so what landed on disk is a rounded copy of the in-memory table. Aliasing the
    /// full-precision cube to the saved path would leave the app rendering something a fresh launch
    /// could not reproduce from that same file — a divergence of exactly the kind this migration
    /// exists to close. The file is authoritative because the file is what persists.
    ///
    /// It is registered as well as re-pointed, because `onSaved` only triggers a rescan when the
    /// destination is inside the configured LUT folder. Saving anywhere else would otherwise re-point
    /// the document at something nothing can resolve.
    ///
    /// Only the LUT that was *just saved* moves. The user can derive, pick something else from the
    /// sidebar, and then save the derive from the still-open sheet; that must not steal the selection.
    private func adoptSavedLUT(at destination: URL) {
        guard let saved = try? CubeLUT(url: destination, category: "Derived") else { return }
        derivedRegistry.register(saved)

        guard let current = document.lut.lutID, current == derive.derivedLUT?.lutID else { return }
        endUndoGrouping()
        updateDocument { $0.lut.lutID = saved.lutID }
    }

    /// Open the first image of the source folder once its scan completes.
    private func openFirstImageWhenScanned() {
        Task {
            await collection.scanCompletion()
            guard let first = collection.items.first, let fileURL = first.url else { return }
            openImage(url: fileURL)
        }
    }

    // MARK: - Error presentation

    /// Surface a user-facing error both as a dismissible alert and in the
    /// status bar. Used for hard failures (load / export / derive / save);
    /// transient preview hiccups stay status-bar-only to avoid alert spam.
    private func presentError(_ message: String) {
        statusMessage = message
        errorMessage = message
    }

    // MARK: - Image loading

    func openImage(url: URL) {
        load(name: url.lastPathComponent, url: url, data: nil)
    }

    private func openImage(url: URL, assetID: PhotoAssetID) {
        load(name: url.lastPathComponent, url: url, data: nil, assetID: assetID)
    }

    /// Decode an image **off the main actor**, then publish it and render the
    /// previews. RAW demosaicing is expensive enough (hundreds of ms) that
    /// doing it inline would freeze the window on every ←/→ step.
    private func load(name: String, url: URL?, data: Data?, assetID: PhotoAssetID? = nil) {
        let assetID = assetID ?? (url.map(PhotoAssetID.file) ?? data.map(PhotoAssetID.data) ?? .data(Data()))
        endUndoGrouping()
        saveActiveDocument()
        activeAssetID = assetID
        let session = editSessions[assetID] ?? PhotoEditSession()
        document = session.document
        activeHistory = session.history
        lastReportedMissingLUT = nil
        lutResolutionStatus = nil
        refreshLUTResolutionStatus()

        sourceRevision &+= 1
        previewCoordinator.cancel()
        previewSurface.clear()
        originalPreviewSurface.clear()
        // Do not let the previous surface briefly show the photo we are leaving while the new
        // source is being decoded.
        sourceImage = nil
        sourceURL = nil
        sourceSize = .zero
        isPreviewInteractionActive = false
        loadTask?.cancel()
        metadataTask?.cancel()
        metadata = ImageMetadata()
        originalPreviewTask?.cancel()
        previewDebounceTask?.cancel()
        capabilitiesTask?.cancel()
        // A pending develop flag describes the image being left; it must not survive onto whatever
        // opens next, or an unrelated first edit on the new image would render a comparison baseline
        // for develop settings that were never actually touched on it.
        pendingDevelopChange = false

        isLoading = true
        statusMessage = "Loading \(name)..."

        loadTask = Task {
            var interval = LumoSignpostInterval(
                .photoSwitch,
                context: LumoTraceContext(sourceFingerprint: name, quality: "interactive")
            )
            defer { interval.end() }

            let decoded: Result<CIImage, Error> = await Task.detached {
                do {
                    if let url {
                        return .success(try ImageDecoder.load(from: url))
                    }
                    if let data {
                        return .success(try ImageDecoder.load(from: data, name: name))
                    }
                    return .failure(ImageError.cannotLoad(name))
                } catch {
                    return .failure(error)
                }
            }.value

            guard !Task.isCancelled else { return }

            switch decoded {
            case .failure(let error):
                self.isLoading = false
                self.presentError("Error: \(error.localizedDescription)")

            case .success(let ci):
                self.sourceImage = ci
                self.sourceURL = url
                self.sourceName = name
                self.sourceSize = ci.extent.size
                // The renderer works from the file, not the decoded image, so a RAW can be
                // re-developed per render. `nativeExtent` comes from the decode we just did.
                if let url {
                    self.imageSource = ImageSource(url: url, nativeExtent: ci.extent.size)
                } else if let data {
                    self.imageSource = ImageSource(data: data, nativeExtent: ci.extent.size)
                } else {
                    self.imageSource = nil
                }
                self.statusMessage = "\(name)  \(Int(ci.extent.width))\u{00D7}\(Int(ci.extent.height))"
                self.isLoading = false

                self.schedulePreview()
                // The visible render is submitted first. The coordinator starts it before this
                // supporting baseline task, preserving the visible-image priority at open.
                self.scheduleOriginalPreview()
                self.refreshMetadata(url: url, data: data)
                self.refreshCapabilities()
            }
        }
    }

    func openImageDialog() {
        let panel = NSOpenPanel()
        panel.title = "Open Image"
        panel.allowedContentTypes = ImageDecoder.supportedTypes
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            collection.clear()
            openImage(url: url)
        }
    }

    // MARK: - Photo import

    func openImage(data: Data, name: String) {
        load(name: name, url: nil, data: data)
    }

    func importFromPhotos() {
        isPhotosPickerPresented = true
    }

    func importPhotosData(_ items: [(name: String, data: Data)]) {
        collection.addFromData(items)
        if let first = items.first {
            openImage(data: first.data, name: first.name)
        }
    }

    /// Choose a folder to use as the persistent image source, scan it (incl.
    /// subfolders), reveal the file browser, and open the first image.
    func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Source Folder"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            openSourceFolder(url: url)
        }
    }

    /// Adopt `url` as the source folder (persisted), reveal the browser, and
    /// open its first image. Shared by the menu/toolbar action and folder drops.
    func openSourceFolder(url: URL) {
        collection.setSourceFolder(url)
        isSourceBrowserPresented = true
        isLibraryGridPresented = true
        collection.beginThumbnailDemand()
        openFirstImageWhenScanned()
    }

    func toggleSourceBrowser() {
        isSourceBrowserPresented.toggle()
    }

    func toggleLibraryGrid() {
        guard collection.isActive else { return }
        isLibraryGridPresented.toggle()
        if isLibraryGridPresented { collection.beginThumbnailDemand() }
    }

    /// Re-scan the current source folder for added/removed files.
    func refreshSource() {
        collection.refresh()
    }

    func selectCollectionImage(at index: Int) {
        guard collection.items.indices.contains(index) else { return }
        collection.select(at: index)
        let item = collection.items[index]

        if let url = item.url {
            openImage(url: url, assetID: item.id)
        } else if let data = item.imageData {
            openImage(data: data, name: item.displayName)
        }
    }

    /// Select a grid cell without leaving the grid. This is what makes a multi-selection useful:
    /// Command-click and Shift-click change the batch while the active photo remains explicit.
    func selectLibraryItem(
        at index: Int,
        modifiers: LibrarySelectionModel.Modifiers = []
    ) {
        collection.select(at: index, modifiers: modifiers)
    }

    /// Apply a culling flag to the focused library asset. Pick/reject use the rapid-cull workflow
    /// and move to the next visible asset; rating changes stay on the current photo.
    @discardableResult
    func setFocusedFlag(_ flag: PhotoFlag, advance: Bool = false) -> Bool {
        let name = collection.selectedItem?.displayName
        let changed = collection.setFlag(flag, advance: advance)
        if changed, let name {
            statusMessage = "\(name): \(flag == .pick ? "Picked" : flag == .reject ? "Rejected" : "Flag cleared")"
        }
        return changed
    }

    @discardableResult
    func setFocusedRating(_ rating: Int) -> Bool {
        let changed = collection.setRating(rating)
        if changed, let item = collection.selectedItem {
            statusMessage = "\(item.displayName): \(rating == 0 ? "Rating cleared" : "Rated \(rating) stars")"
        }
        return changed
    }

    @discardableResult
    func undoCullingChange() -> Bool {
        collection.undoLastCullingChange()
    }

    /// Enter the editor for the grid's active photo. Thumbnail availability is not a prerequisite;
    /// `openImage` starts the existing asynchronous RAW load immediately.
    func openActiveCollectionImage() {
        guard let item = collection.selectedItem else { return }
        isLibraryGridPresented = false
        if let url = item.url {
            openImage(url: url, assetID: item.id)
        } else if let data = item.imageData {
            openImage(data: data, name: item.displayName)
        }
    }

    func selectPreviousImage() {
        guard collection.isActive else { return }
        let prev = collection.selectedIndex
        collection.selectPrevious()
        if collection.selectedIndex != prev {
            selectCollectionImage(at: collection.selectedIndex)
        }
    }

    func selectNextImage() {
        guard collection.isActive else { return }
        let prev = collection.selectedIndex
        collection.selectNext()
        if collection.selectedIndex != prev {
            selectCollectionImage(at: collection.selectedIndex)
        }
    }

    // MARK: - LUT selection

    func selectLUT(_ lut: CubeLUT?) {
        // A derived LUT is in no library, so nothing but the registry can resolve it later. Remember
        // it rather than replacing the last one: a document made now must still resolve after the
        // user derives again.
        if let lut, lut.lutID.isDerived { derivedRegistry.register(lut) }
        endUndoGrouping()
        updateDocument { $0.lut.lutID = lut?.lutID }
        refreshLUTResolutionStatus()
    }

    /// Select a Look by its stable document ID. The browser binds to IDs rather than resolved LUT
    /// values so the explicit None row and a missing file remain distinct selections.
    func selectLUT(id: LUTID?) {
        guard let id else {
            selectLUT(nil)
            return
        }
        guard let lut = resolvedLUT(id) else { return }
        selectLUT(lut)
    }

    /// Mutate the document and re-render.
    ///
    /// The only way to reach `rawDevelop` and `adjustments` today. The inspector that will drive them
    /// from the UI is Step 10; until it exists this is the seam those fields are tested through, and
    /// it is what the inspector will call. Keeping `document` `private(set)` behind it means every
    /// mutation goes through one place that knows to re-render.
    func updateDocument(_ transform: (inout EditDocument) -> Void) {
        updateDocument(debounced: false, transform)
    }

    /// Mutate the document and re-render, optionally coalescing a burst of edits into one render.
    ///
    /// **`debounced: true` is for continuous controls only** — a slider drag, where the user
    /// produces tens of values per second and only the one they settle on matters. `PHASE2_SPEC.md`
    /// §6 is explicit that open and filmstrip navigation must stay immediate, and discrete controls
    /// (toggles, resets) should too: a checkbox that lagged 60 ms would feel broken.
    ///
    /// The document itself is updated **immediately** either way. Only the render is deferred, so
    /// the control stays glued to the pointer and `document` is always the truth. Deferring the
    /// document as well would mean a read-back mid-drag saw a stale value.
    ///
    /// Worth the machinery because a develop change costs *two* renders — `scheduleOriginalPreview`
    /// as well as `schedulePreview`, since the comparison baseline moves with develop.
    func updateDocument(debounced: Bool, _ transform: (inout EditDocument) -> Void) {
        var updated = document
        transform(&updated)
        guard updated != document else { return }

        let developChanged = updated.rawDevelop != document.rawDevelop
        activeHistory.recordChange(from: document, to: updated)
        document = updated
        refreshLUTResolutionStatus()
        saveActiveDocument()
        documentRevision &+= 1
        // A supporting baseline from the previous state is no longer useful once the document
        // changes. Cancel it before the new visible request is submitted; a develop edit will queue
        // the correct baseline after its settled visible result publishes.
        originalPreviewTask?.cancel()
        // OR'd in rather than assigned: a call earlier in a coalesced burst may have changed
        // `rawDevelop` even though *this* call didn't, and only the last call's task survives to
        // fire (see `pendingDevelopChange`'s doc comment).
        pendingDevelopChange = pendingDevelopChange || developChanged

        guard debounced else {
            schedulePreview()
            return
        }

        if isPreviewInteractionActive {
            scheduleInteractivePreview()
        } else {
            scheduleSettledPreviewAfterDebounce()
        }
    }

    /// Resolve a document's LUT reference: prefer the latest library scan, then the in-memory
    /// registry. The library must win for file-backed IDs: the registry retains saved derived LUTs
    /// so they work outside the library folder, but must not mask a replacement found by a scan.
    private func resolvedLUT(_ id: LUTID?) -> CubeLUT? {
        guard let id else { return nil }
        if let scanned = library.allLUTs.first(matching: id) { return scanned }
        return derivedRegistry.lut(for: id)
    }

    /// Report one missing-reference transition at a time. Waiting for scan completion avoids a false
    /// warning while the library is still assembling, while the document retains the unresolved ID.
    private var lastReportedMissingLUT: LUTID?

    private func refreshLUTResolutionStatus() {
        guard let id = document.lut.lutID else {
            lastReportedMissingLUT = nil
            lutResolutionStatus = nil
            return
        }
        guard !library.isScanning else { return }
        guard resolvedLUT(id) == nil else {
            lastReportedMissingLUT = nil
            lutResolutionStatus = nil
            return
        }
        guard lastReportedMissingLUT != id else { return }

        let name = id.isDerived ? "derived look" : URL(fileURLWithPath: id.raw).lastPathComponent
        let message = "LUT “\(name)” is unavailable; the stored reference was kept."
        lastReportedMissingLUT = id
        lutResolutionStatus = message
        statusMessage = message
    }

    func selectPreviousLUT() {
        guard let current = selectedLUT,
              let idx = library.allLUTs.firstIndex(of: current),
              idx > 0 else { return }
        selectLUT(library.allLUTs[idx - 1])
    }

    func selectNextLUT() {
        guard let current = selectedLUT else {
            if let first = library.allLUTs.first { selectLUT(first) }
            return
        }
        guard let idx = library.allLUTs.firstIndex(of: current),
              idx < library.allLUTs.count - 1 else { return }
        selectLUT(library.allLUTs[idx + 1])
    }

    /// Reset only the Look stage. Other inspector panels remain untouched, and the operation is one
    /// reversible history entry for the active photo.
    func resetLook() {
        endUndoGrouping()
        updateDocument { $0.lut = .none }
    }

    /// LUT terminology remains available to callers that have not adopted the user-facing Look
    /// name yet.
    func resetLUT() {
        resetLook()
    }

    // MARK: - LUT application

    private func applyLUT() {
        schedulePreview()
    }

    /// Set the LUT strength (0...1) and re-render the preview. Safe to call on
    /// every slider tick: the re-render is debounced and the previous one is
    /// cancelled, so a full-travel drag costs a handful of renders, not one per
    /// pixel of travel.
    func setLUTIntensity(_ value: Double) {
        let clamped = max(0, min(1, value))
        guard clamped != document.lut.intensity else { return }
        let oldDocument = document
        document.lut.intensity = clamped
        activeHistory.recordChange(from: oldDocument, to: document)
        saveActiveDocument()
        documentRevision &+= 1
        originalPreviewTask?.cancel()

        if isPreviewInteractionActive {
            scheduleInteractivePreview()
        } else {
            scheduleSettledPreviewAfterDebounce()
        }
    }

    // MARK: - Preview

    /// Backing pixels of the visible canvas. PreviewView updates this from its live geometry;
    /// the fallback is only used before the first layout pass.
    private var previewBackingSize = CGSize(width: 1600, height: 1200)
    private static let intensityDebounceMs = 60

    /// What the main preview panel should currently show, as a render request.
    ///
    /// While Space is held that is the **comparison baseline** — the same document with the look
    /// removed and develop kept (§8.5). Both sides therefore share a `rawDevelop`, so the swap reuses
    /// the engine's developed source instead of re-developing the RAW.
    ///
    /// One accessor rather than the same ternary at each call site: the histogram is supposed to
    /// describe the pixels on screen, and it stopped doing so precisely because it derived its image
    /// separately. Reading the request from one place is what makes that structural.
    private var displayRequest: (document: EditDocument, lut: CubeLUT?) {
        isShowingOriginal ? (document.originalForComparison, nil) : (document, selectedLUT)
    }

    /// Render the document for display.
    ///
    /// **This is the Step 5 cutover.** The preview no longer grades a baked `CIImage` on the main
    /// actor and rasterizes it through the old `ImageProcessor`; it hands the whole document to
    /// `PreviewCoordinator`, which selects the interactive or settled quality and asks
    /// `RenderEngine` to evaluate the graph inside its actor.
    private func schedulePreview() {
        guard let imageSource else {
            previewSurface.clear()
            return
        }

        let (requested, lut) = displayRequest
        previewCoordinator.submit(RenderRequest(
                source: imageSource, document: requested, lut: lut,
                targetSize: previewBackingSize, quality: .preview, output: .raster, space: .current
            ), phase: .settled)
    }

    /// A viewport-sized interactive render. `PreviewCoordinator` drops superseded values and
    /// promotes the last value to a normal `.preview` render after the quiet period.
    private func scheduleInteractivePreview() {
        guard let imageSource else { return }
        let (requested, lut) = displayRequest
        previewCoordinator.submit(RenderRequest(
            source: imageSource, document: requested, lut: lut,
            targetSize: previewBackingSize, quality: .interactive, output: .raster, space: .current
        ), phase: .interactive)
    }

    /// Called by the persistent preview surface after layout. Keeping this as value state avoids
    /// publishing a new image merely because the window changed size.
    func updatePreviewBackingSize(_ size: CGSize) {
        let width = size.width.rounded(.down)
        let height = size.height.rounded(.down)
        guard width >= 1, height >= 1,
              width.isFinite, height.isFinite,
              abs(width - previewBackingSize.width) > 1 || abs(height - previewBackingSize.height) > 1
        else { return }
        previewBackingSize = CGSize(width: width, height: height)
        guard imageSource != nil else { return }
        if isPreviewInteractionActive {
            scheduleInteractivePreview()
        } else {
            schedulePreview()
        }
    }

    private func scheduleSettledPreviewAfterDebounce() {
        previewDebounceTask?.cancel()
        previewDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(Self.intensityDebounceMs))
            guard !Task.isCancelled else { return }
            self.schedulePreview()
        }
    }

    func beginPreviewInteraction() {
        beginUndoGrouping()
        isPreviewInteractionActive = true
        previewCoordinator.beginInteraction()
    }

    func endPreviewInteraction() {
        isPreviewInteractionActive = false
        previewDebounceTask?.cancel()
        previewDebounceTask = nil
        previewCoordinator.endInteraction()
        endUndoGrouping()
    }

    /// Read-only seam for controls implemented in extensions. Keeping the stored interaction flag
    /// private preserves ownership of the lifecycle while allowing curve mutations to choose the
    /// same immediate-vs-interactive render policy as the built-in sliders.
    var isToneCurvePreviewInteractionActive: Bool { isPreviewInteractionActive }

    // MARK: - Undo and reset

    /// Start one history entry for a continuous slider gesture.
    func beginUndoGrouping() {
        activeHistory.beginGrouping(document: document)
    }

    /// Finish a continuous gesture. A gesture that did not change the document is not recorded.
    func endUndoGrouping() {
        activeHistory.endGrouping(document: document)
        saveActiveDocument()
    }

    var canUndo: Bool { activeHistory.canUndo }
    var canRedo: Bool { activeHistory.canRedo }

    func undo() {
        endUndoGrouping()
        guard let restored = activeHistory.undo(current: document) else { return }
        applyHistoryDocument(restored)
    }

    func redo() {
        endUndoGrouping()
        guard let restored = activeHistory.redo(current: document) else { return }
        applyHistoryDocument(restored)
    }

    /// Return every edit on the current photo to its neutral state as one reversible operation.
    func resetPhoto() {
        endUndoGrouping()
        updateDocument { $0 = EditDocument() }
    }

    private func applyHistoryDocument(_ restored: EditDocument) {
        let developChanged = restored.rawDevelop != document.rawDevelop
        document = restored
        refreshLUTResolutionStatus()
        saveActiveDocument()
        originalPreviewTask?.cancel()
        pendingDevelopChange = false
        if developChanged { scheduleOriginalPreview() }
        schedulePreview()
    }

    private func publishPreview(_ publication: PreviewCoordinator.Publication) {
        guard publication.request.source == imageSource else { return }
        if let gpuImage = publication.gpuImage {
            previewSurface.present(gpuImage, space: publication.request.space,
                                   revision: publication.revision,
                                   telemetry: previewCoordinator.telemetry,
                                   source: publication.request.source,
                                   quality: publication.request.quality)
        } else if let cgImage = publication.image {
            // Non-GPU conformers retain a raster compatibility seam, but it terminates at the
            // same persistent surface. Production RenderEngine publishes `gpuImage`, so this does
            // not allocate or publish an NSImage on the normal preview path.
            previewSurface.present(CIImage(cgImage: cgImage), space: publication.request.space,
                                   revision: publication.revision,
                                   telemetry: previewCoordinator.telemetry,
                                   source: publication.request.source,
                                   quality: publication.request.quality)
        }
        guard publication.gpuImage != nil || publication.image != nil else {
            if publication.phase == .settled {
                statusMessage = "Could not render \(sourceName)"
            }
            return
        }

        // The comparison baseline is supporting work. Queue it only after the visible settled
        // result has published so a navigation/edit burst cannot put it ahead of the main image.
        if publication.phase == .settled {
            if pendingDevelopChange {
                pendingDevelopChange = false
                scheduleOriginalPreview()
            }
            updateHistogram()
        }
    }

    /// Rasterize the comparison baseline for the side-by-side left panel. Only needs to re-run when
    /// the image or the develop settings change — not when the look does.
    private func scheduleOriginalPreview() {
        guard let imageSource else {
            originalPreviewTask?.cancel()
            originalPreviewSurface.clear()
            return
        }
        let baseline = document.originalForComparison
        let box = previewBackingSize
        let sourceRevision = self.sourceRevision
        let documentRevision = self.documentRevision

        originalPreviewTask = Task { [engine] in
            let request = RenderRequest(
                source: imageSource, document: baseline, lut: nil,
                targetSize: box, quality: .preview, output: .raster, space: .current
            )
            let gpuImage = await engine.makeCIImage(request)
            if let gpuImage {
                guard !Task.isCancelled,
                      sourceRevision == self.sourceRevision,
                      documentRevision == self.documentRevision,
                      self.imageSource == imageSource else { return }
                self.originalPreviewSurface.present(gpuImage, space: request.space)
                return
            }
            let cgImage = await engine.makeCGImage(request)
            guard !Task.isCancelled,
                  sourceRevision == self.sourceRevision,
                  documentRevision == self.documentRevision,
                  self.imageSource == imageSource,
                  let cgImage else { return }
            self.originalPreviewSurface.present(CIImage(cgImage: cgImage), space: request.space)
        }
    }

    /// Toggle between original and LUT preview (for Space-hold comparison).
    func showOriginal(_ show: Bool) {
        guard show != isShowingOriginal else { return }
        isShowingOriginal = show
        schedulePreview()
    }

    func toggleSideBySide() {
        isSideBySide.toggle()
    }

    // MARK: - Info inspector (EXIF + histogram)

    func toggleInspector() {
        isInspectorPresented.toggle()
    }

    /// Recompute the histogram for the currently displayed image. No-op unless the Info tab of an
    /// open inspector is on screen. Cancellable, so dragging the intensity slider stays smooth.
    ///
    /// **Step 6 cut this over with export.** It used to tally `processedImage` — a full-resolution
    /// neutral decode with only the LUT on it — while the screen showed develop and adjustments as
    /// well. Deleting `processedImage` forced the choice, and describing the wrong image is not a
    /// state worth carrying to Step 7: the histogram now renders the *same document at the same
    /// scale* the preview does, which is what `document(forDisplay:)` exists to guarantee.
    ///
    /// Passing the preview box rather than a histogram-sized scale is deliberate — see
    /// `RenderEngine.histogram`, which shares the developed-source memo with the on-screen render
    /// instead of evicting it every tally.
    private func updateHistogram() {
        // Both halves of the gate: an inspector parked on Develop shows no histogram, so tallying
        // one on every settled render of a slider drag is pure waste.
        guard isInspectorPresented, inspectorTab == .info else { return }
        guard let imageSource else {
            histogram = nil
            return
        }
        let (requested, lut) = displayRequest
        let box = previewBackingSize
        let sourceRevision = self.sourceRevision
        let documentRevision = self.documentRevision

        histogramTask?.cancel()
        histogramTask = Task { [engine] in
            let result = await engine.histogram(
                source: imageSource, document: requested, lut: lut,
                scale: .preview(maxSize: box), space: .current, maxDimension: 512
            )
            guard !Task.isCancelled,
                  sourceRevision == self.sourceRevision,
                  documentRevision == self.documentRevision,
                  self.imageSource == imageSource else { return }
            self.histogram = result
        }
    }

    /// Read EXIF/TIFF/GPS metadata off the main actor and publish it.
    private func refreshMetadata(url: URL?, data: Data?) {
        let revision = sourceRevision
        metadataTask?.cancel()
        metadataTask = Task { [weak self] in
            let meta = await Task.detached {
                if let url {
                    return ImageMetadata.read(from: url)
                }
                if let data {
                    return ImageMetadata.read(from: data)
                }
                return ImageMetadata()
            }.value
            guard !Task.isCancelled, let self, self.sourceRevision == revision else { return }
            self.metadata = meta
        }
    }

    /// Ask the engine what this image's decoder supports.
    ///
    /// Runs alongside the preview render rather than in front of it: the panel can appear a frame
    /// late, but first pixels should not wait on a capability question.
    private func refreshCapabilities() {
        capabilitiesTask?.cancel()
        rawCapabilities = nil

        guard let imageSource else { return }
        let revision = sourceRevision
        capabilitiesTask = Task { [engine] in
            let capabilities = await engine.rawCapabilities(for: imageSource)
            guard !Task.isCancelled,
                  revision == self.sourceRevision,
                  self.imageSource == imageSource else { return }
            self.rawCapabilities = capabilities
        }
    }

    // MARK: - Export

    /// Export the open image at full resolution.
    ///
    /// **The Step 6 cutover.** What goes to disk is now the same `EditDocument` the screen is
    /// rendering, at `.full` instead of `.preview` — one argument apart, through one funnel. Before,
    /// this handed over a baked `CIImage` that carried the LUT and nothing else, so develop and
    /// adjustments reached the preview and silently did not reach the file.
    ///
    /// Note it exports `document`, not `displayRequest` — holding Space to compare should not change
    /// what ⌘S writes.
    func exportDialog() {
        guard let request = exportRequest else {
            statusMessage = "Open an image first"
            return
        }
        export.exportDialog(
            source: request.source,
            document: request.document,
            lut: request.lut,
            suggestedBaseName: request.baseName
        )
    }

    /// What ⌘S would export, without running a panel.
    ///
    /// Internal rather than private because `NSSavePanel` cannot run headless, so this is the only
    /// way to assert the part of `exportDialog` that has content — *which* document goes to disk. The
    /// wrapper around it is the two lines the panel makes untestable, which is the same trade
    /// `docs/CODE_REVIEW.md` §5 already records for every other panel in the app.
    var exportRequest: (source: ImageSource, document: EditDocument, lut: CubeLUT?, baseName: String)? {
        guard let imageSource else { return nil }
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "image"
        return (
            source: imageSource,
            document: document,
            lut: selectedLUT,
            baseName: ExportCoordinator.exportBaseName(source: base, lut: selectedLUT)
        )
    }

    /// Apply the current look to every imported image and export them all to a
    /// chosen folder.
    ///
    /// Cut over with the single export, and for the same reason: `performBatchExport` used to load
    /// and grade each file itself, so fixing only the single path would have left Export All writing
    /// the old, develop-less render.
    func batchExportDialog() {
        let request = batchExportRequest
        export.batchExportDialog(items: request.items, document: request.document, lut: request.lut)
    }

    /// What Export All would write, without running a panel. Internal for the same reason
    /// `exportRequest` is.
    var batchExportRequest: (items: [ExportCoordinator.BatchItem], document: EditDocument, lut: CubeLUT?) {
        // Snapshot only the Sendable bits — avoid carrying NSImage thumbnails
        // across the actor boundary.
        let items = collection.items.map {
            ExportCoordinator.BatchItem(url: $0.url, data: $0.imageData, name: $0.displayName)
        }
        return (items: items, document: document, lut: selectedLUT)
    }

    // MARK: - Recipe extractor

    func presentRecipeExtractor() {
        derive.present()
    }

    func dismissRecipeExtractor() {
        derive.dismiss()
    }

    func deriveRecipe(rawURL: URL, jpgURL: URL) {
        derive.derive(rawURL: rawURL, jpgURL: jpgURL)
    }

    func saveDerivedLUT() {
        derive.saveDialog()
    }

    // MARK: - LUT folder

    func chooseLUTFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select LUT Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            library.setFolder(url)
        }
    }

    private func saveActiveDocument() {
        guard let activeAssetID else { return }
        editSessions[activeAssetID] = PhotoEditSession(document: document, history: activeHistory)
    }
}
