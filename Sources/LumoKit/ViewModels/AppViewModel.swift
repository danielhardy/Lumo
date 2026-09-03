import Foundation
import CoreImage
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct PhotosImportProgress: Equatable, Sendable {
    enum Phase: String, Sendable {
        case transferring
        case inserting

        var label: String {
            switch self {
            case .transferring: return "Transferring"
            case .inserting: return "Adding"
            }
        }
    }

    let total: Int
    var processed: Int
    var imported: Int
    var failed: Int
    var currentName: String?
    var phase: Phase

    var fraction: Double {
        guard total > 0 else { return 1 }
        return min(1, Double(processed) / Double(total))
    }
}

struct MediaVolumeImportProgress: Equatable, Sendable {
    let total: Int
    var processed: Int
    var imported: Int
    var skipped: Int
    var currentName: String?
    var cancelled: Bool

    var fraction: Double {
        guard total > 0 else { return 1 }
        return min(1, Double(processed) / Double(total))
    }
}

/// Lifecycle state for the source-statistics-driven Auto action.
enum AutoAdjustmentState: Equatable, Sendable {
    case unavailable(String)
    case ready
    case analyzing
    case failed(String)

    var message: String {
        switch self {
        case .unavailable(let message), .failed(let message): return message
        case .ready: return "Analyze the source and replace global Light and Color with a conservative baseline."
        case .analyzing: return "Analyzing the source for Auto adjustments…"
        }
    }
}

/// Central state for the Lumo app.
@MainActor
public final class AppViewModel: ObservableObject, LookPreviewProviding {

    /// Inspector presentation state has its own observation boundary. The editor model still
    /// owns histogram scheduling and tab validity, but changing the inspector chrome does not
    /// need to publish through the model observed by the library and canvas shells.
    @MainActor
    final class InspectorState: ObservableObject {
        @Published var isPresented = false
        @Published var tab: InspectorTab = .info
    }

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

    /// The last copied value-state payload. It contains no image or rendered data, so it remains
    /// safe to apply to several destinations and keeps future selective-copy UI on one stable seam.
    @Published private(set) var editClipboard: EditClipboardPayload?

    var canPasteEdits: Bool { editClipboard != nil }

    /// The most recent persistence warning. A damaged edit catalog must not prevent the source
    /// image from opening, but it should remain visible to the user.
    @Published private(set) var editStoreStatus: String?

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

    /// Whether the capability answer belongs to the currently selected source. This is separate
    /// from `rawCapabilities == nil`: a RAW can still be probing, or its decoder can answer that it
    /// has no actionable develop controls.
    @Published private(set) var capabilitiesProbeCompleted = false

    /// What the develop panel should be showing right now. The probe state is distinct from a
    /// completed answer that offers no usable controls.
    ///
    /// `rawCapabilities` is nil while probing and can also be nil after a decoder answers that it
    /// has no actionable controls. `refreshCapabilities()` clears it synchronously on every open
    /// and refills it 25–170 ms later, so a RAW opened with the Develop tab already showing retains an
    /// honest loading state instead of briefly claiming "No develop stage". When a new source makes
    /// the active tab unavailable, navigation repairs the selection to Info.
    ///
    /// Deriving the state here rather than in the view is what makes it testable: this repo has no
    /// SwiftUI view tests, so a distinction that lives only in a `ViewBuilder` cannot be asserted.
    /// `DevelopInspectorView` is a `switch` over this value and nothing else.
    ///
    /// This — rather than a widened `imageSource` — is the whole of what the panel needs from the
    /// source: not the backing bytes, not the native extent, only whether a develop stage exists at
    /// all. See `sourceIsRAW` for the widening that does happen, and why it is a `Bool`.
    var developPanelState: DevelopPanelState {
        guard sourceImage != nil, sourceIsRAW else { return .noDevelopStage }
        return DevelopPanelState(
            sourceIsRAW: sourceIsRAW,
            capabilities: rawCapabilities,
            probeCompleted: capabilitiesProbeCompleted
        )
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

    /// The states of the develop panel. See `AppViewModel.developPanelState`.
    enum DevelopPanelState: Equatable, Sendable {
        /// Not a RAW (or nothing open): there is no develop stage to offer, and saying so is honest.
        case noDevelopStage
        /// A RAW whose capability probe has not landed yet. The controls are coming, so the panel
        /// must not claim there are none.
        case probing
        /// A RAW, probed. The panel draws `capabilities.availableControls`.
        case ready(RAWCapabilities)

        /// A RAW decoder answered, but did not offer anything this panel can edit.
        case noSupportedControls

        var offersDevelopTab: Bool {
            switch self {
            case .probing:
                return true
            case .ready(let capabilities):
                return !capabilities.availableControls.isEmpty
            case .noDevelopStage, .noSupportedControls:
                return false
            }
        }

        /// Preserve the original two-input mapping for callers that use it as a pure pre-probe
        /// state table. Production uses the overload below once it has an explicit completion bit.
        init(sourceIsRAW: Bool, capabilities: RAWCapabilities?) {
            if let capabilities {
                self = .ready(capabilities)
            } else {
                self = sourceIsRAW ? .probing : .noDevelopStage
            }
        }

        /// **The mapping, in one place, as a pure function.** A completed RAW answer of `nil` is
        /// not allowed to remain in `.probing`.
        init(sourceIsRAW: Bool, capabilities: RAWCapabilities?, probeCompleted: Bool) {
            if !sourceIsRAW {
                self = .noDevelopStage
                return
            }
            guard probeCompleted || capabilities != nil else {
                self = .probing
                return
            }
            guard let capabilities else {
                self = .noSupportedControls
                return
            }
            self = capabilities.availableControls.isEmpty
                ? .noSupportedControls
                : .ready(capabilities)
        }
    }

    /// Tabs for the current image. Develop remains visible during a RAW capability probe so the
    /// picker can honestly expose the loading state, but it disappears for standard images and for
    /// RAW decoders with no actionable controls.
    var availableInspectorTabs: [InspectorTab] {
        InspectorTab.availableTabs(
            hasImage: sourceImage != nil,
            developPanelState: developPanelState
        )
    }

    private var capabilitiesTask: Task<Void, Never>?

    private var editSessions: [PhotoAssetID: PhotoEditSession] = [:]
    /// Changes made while a source is being prepared. A late edit-store result may fill a missing
    /// session, but it must never replace this newer in-memory state.
    private var editSessionRevisions: [PhotoAssetID: UInt64] = [:]
    private var nextEditSessionRevision: UInt64 = 0
    private var activeAssetID: PhotoAssetID?
    private var activeHistory = EditHistory()
    private var activeSourceReference: EditSourceReference?
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private struct PendingPersistence: Equatable {
        let document: EditDocument
        let reference: EditSourceReference
        let reportsStatus: Bool
        let force: Bool
    }
    private var pendingPersistence: [PhotoAssetID: PendingPersistence] = [:]
    /// A gesture is checkpointed at most 250 ms apart. This bounds the amount of recent work that
    /// can be lost while retaining immediate live document/render updates.
    private static let persistenceCheckpoint: Duration = .milliseconds(250)

    var pendingPersistenceCount: Int { pendingPersistence.count }
    var peakPendingPersistenceCount: Int { peakPendingPersistence }
    private var peakPendingPersistence = 0

    /// Source generation prevents delayed work from a previous navigation selection from publishing
    /// into the new image, even if the source values happen to compare equal.
    private var sourceRevision: UInt64 = 0
    /// Document generation guards the primary visible render and histogram publications.
    private var documentRevision: UInt64 = 0
    /// Display generation guards histogram work against a newer request, including comparison
    /// mode and render-scale changes that do not change the edit document.
    private var displayRevision: UInt64 = 0
    /// Baseline generation changes when the source or a comparison-frame stage (develop/crop)
    /// changes. Look-stage edits must not invalidate an in-flight baseline that is still correct.
    private var comparisonRevision: UInt64 = 0
    /// The last settled request confirmed by the presentation surface. Supporting work is never
    /// admitted before this lifecycle boundary.
    private var lastPresentedVisibleRequest: RenderRequest?
    /// The newest settled request accepted by the preview surface. Mode entry may use this current
    /// candidate before drawable confirmation, but it must never fall back to an older document.
    private var lastPublishedVisibleRequest: RenderRequest?
    private var isPreviewInteractionActive = false

    /// Whether any call since the last fired render changed a comparison-frame stage.
    ///
    /// A coalesced burst of edits accumulates this flag while the preview coordinator keeps only the
    /// newest visible request. A baseline is released after that settled visible request, so an
    /// earlier develop/crop edit in the burst is not lost when a later tick supersedes its value.
    private var pendingDevelopChange = false

    /// LUTs a document can reference that no folder scan produces — a freshly derived LUT, and the
    /// file it becomes once saved. See `DerivedLUTRegistry`; this is the Step 9 replacement for the
    /// single `scratchLUT` slot that stood here.
    private var derivedRegistry = DerivedLUTRegistry()

    /// The selected Look resolved from the active photo's persisted `LUTID`. Resolution is
    /// deliberately fresh: a library rescan may replace the in-memory `CubeLUT`, but it must not
    /// change the document's reference (§4.3).
    var selectedLook: CubeLUT? { resolvedLUT(document.lut.lutID) }

    /// The active photo's persisted Look strength.
    var lookIntensity: Double { document.lut.intensity }

    /// Compatibility seam for render and test callers that still use the model's historical LUT
    /// name. The user-facing editor is routed through `selectedLook`.
    var selectedLUT: CubeLUT? { selectedLook }

    /// Compatibility seam for callers that still use the model's historical LUT name.
    var lutIntensity: Double { lookIntensity }

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

    /// Whether the transient A/B comparison — especially the Space-hold — has a meaningful
    /// before/after to show. Side-by-side presentation has a separate source-availability gate
    /// because an identity document still renders valid source pixels into both panes.
    /// The document owns the exact visible-stage rule and the matching `comparisonBaseline`, so
    /// Light, Color, Effects, adjustment nodes, and LUT intensity cannot drift apart at this gate.
    ///
    var isComparisonAvailable: Bool { document.hasVisibleLookEdits }

    @Published var isShowingOriginal: Bool = false
    /// The user's preferred comparison presentation. This is a display preference rather than
    /// per-photo edit state, so changing photos does not reset it and a new view model can restore
    /// it from `UserDefaults`.
    @Published var isSideBySide: Bool = false {
        didSet {
            guard isSideBySide != oldValue else { return }
            preferences.set(isSideBySide, forKey: Self.comparisonModeKey)
        }
    }
    /// Side-by-side is a retained presentation preference. An identity document still has valid
    /// source pixels, so it can populate both panes even though there is no meaningful before/after
    /// for the transient Space comparison.
    var isSideBySideVisible: Bool { isSideBySide && sourceImage != nil }

    /// The visible render is owned by these surfaces, not published image values on this model.
    let previewSurface = PreviewSurface()
    let originalPreviewSurface = PreviewSurface()

    /// High-frequency canvas and transient crop state live outside the broad application
    /// publisher. Only the views that observe `canvasState` reevaluate for pointer interaction.
    let canvasState = CanvasInteractionState()

    /// Inspector chrome has a separate observation boundary for the same reason. The view model
    /// keeps compatibility accessors below so existing commands and tests retain their API while
    /// SwiftUI views can observe the narrow state object directly.
    let inspectorState = InspectorState()

    var canvasNavigation: CanvasNavigation { canvasState.navigation }
    var isCropToolActive: Bool { canvasState.isCropToolActive }
    var cropDraft: CGRect? { canvasState.cropDraft }
    var cropAspectRatio: CropAspectRatio { canvasState.cropAspectRatio }

    var isInspectorPresented: Bool {
        get { inspectorState.isPresented }
        set { inspectorState.isPresented = newValue }
    }

    var inspectorTab: InspectorTab {
        get { inspectorState.tab }
        set { inspectorState.tab = newValue }
    }

    var hasCropAdjustments: Bool { !document.crop.isIdentity }

    /// Inspector visibility. Computing the histogram is gated on this — plus on the Info tab being
    /// the one on screen — so we don't tally pixels for a panel nobody's looking at.
    enum InspectorTab: String, CaseIterable, Sendable {
        case info, light, develop, adjust
        case effects
        case look

        /// The view surface selected by this tab. Keep `.adjust` as the stored compatibility case;
        /// its photographer-facing name is Color.
        enum Content: Equatable, Sendable {
            case info, light, develop, color, effects, look
        }

        var content: Content {
            switch self {
            case .info: return .info
            case .light: return .light
            case .develop: return .develop
            case .adjust: return .color
            case .effects: return .effects
            case .look: return .look
            }
        }

        var iconName: String {
            switch self {
            case .info: return "info.circle"
            case .light: return "sun.max"
            case .develop: return "camera.aperture"
            case .adjust: return "paintpalette"
            case .effects: return "sparkles"
            case .look: return "wand.and.stars"
            }
        }

        var title: String {
            switch self {
            case .info: return "Info"
            case .light: return "Light"
            case .develop: return "Develop"
            case .adjust: return "Color"
            case .effects: return "Effects"
            case .look: return "Look"
            }
        }

        /// Describes the panel's purpose for compact icon-only navigation controls.
        var purpose: String {
            switch self {
            case .info: return "Histogram and photo metadata"
            case .light: return "Tone and RGB curve adjustments"
            case .develop: return "RAW decoder controls"
            case .adjust: return "Color adjustments"
            case .effects: return "Texture, clarity, and dehaze effects"
            case .look: return "Browse and apply a Look"
            }
        }

        var helpText: String { "\(title): \(purpose)" }

        static func availableTabs(
            hasImage: Bool,
            developPanelState: DevelopPanelState
        ) -> [InspectorTab] {
            guard hasImage else { return [] }
            return allCases.filter { tab in
                tab != .develop || developPanelState.offersDevelopTab
            }
        }
    }
    /// Source-folder file browser panel visibility.
    @Published var isSourceBrowserPresented: Bool = false
    /// The visible workspace. Library selection, the active edit document, and render surfaces
    /// remain owned by their existing collaborators; this value only composes those surfaces.
    @Published private(set) var navigation = NavigationState()

    /// EXIF/TIFF/GPS metadata of the loaded image, read at load time.
    @Published var metadata: ImageMetadata = ImageMetadata()
    /// Histogram of the currently displayed image (graded result, or original
    /// while comparing). `nil` until computed / when no image is loaded.
    @Published var histogram: HistogramData?
    /// A nil histogram is otherwise ambiguous: it can mean loading, cancellation, an
    /// unsupported source, or a failed calculation. Keep the terminal UI state explicit.
    @Published private(set) var isHistogramLoading = false
    @Published private(set) var histogramErrorMessage: String?
    private var histogramTaskRevision: UInt64?
    private var histogramTaskRequest: RenderRequest?

    /// Auto has its own analysis lifecycle rather than borrowing the Info histogram's loading flag:
    /// an Auto request must not make the histogram spinner appear to be waiting on unrelated work.
    @Published private(set) var autoAdjustmentState: AutoAdjustmentState = .unavailable(
        "Open a supported photo to enable Auto."
    )
    private var autoAdjustmentTask: Task<Void, Never>?

    @Published var isLoading: Bool = false
    enum PreviewState: Equatable, Sendable {
        case empty
        case loading
        case ready
        case failed
    }
    /// Source preparation and preview presentation are separate async stages. This state keeps
    /// the transparent source marker from making a not-yet-presented canvas look like a black one.
    @Published private(set) var previewState: PreviewState = .empty
    @Published var statusMessage: String = "Open an image to get started"

    /// Non-nil when a hard failure should be surfaced as a dismissible alert.
    /// Bound to an `.alert` in ContentView; cleared when the user dismisses it.
    @Published var errorMessage: String?

    @Published var isPhotosPickerPresented: Bool = false
    /// Non-nil while the Photos picker task is transferring payloads. The collection itself keeps
    /// successful originals visible as soon as they arrive; this state only describes the picker
    /// operation and is cleared once the provider has finished or cancellation was requested.
    @Published private(set) var photosImportProgress: PhotosImportProgress?
    /// Presentation is a property of the import operation, not of each item. This prevents a
    /// later streamed arrival (or a second load triggered by metadata work) from reopening or
    /// retargeting the inspector after the first accepted item has established the active photo.
    private var didPresentInspectorForPhotosImport = false

    /// Removable volumes are discovered independently of the selector so the Import menu can name
    /// mounted volumes that contain supported images, or offer a permission-recovery path when
    /// the sandbox cannot inspect a volume until the user selects it.
    @Published private(set) var removableMediaVolumes: [MediaVolume] = []
    @Published var isRemovableMediaSelectorPresented = false
    @Published private(set) var removableMediaVolume: MediaVolume?
    @Published private(set) var removableMediaFiles: [MediaVolumeFile] = []
    @Published private(set) var removableMediaWarnings: [String] = []
    @Published private(set) var isRemovableMediaScanning = false
    @Published private(set) var removableMediaSelection = MediaVolumeSelectionModel()
    @Published private(set) var removableMediaImportProgress: MediaVolumeImportProgress?

    // MARK: - Owned state

    public let settings: LumoSettings
    let library: LUTLibrary
    let workScheduler: ImageWorkScheduler
    let lookPreviewCoordinator: LookPreviewCoordinator
    let collection: ImageCollection
    let editStore: EditDocumentStore
    /// Writing images to disk — the single export, the batch run, and naming. Production exports
    /// use an isolated RenderEngine lane while preserving the same render request funnel.
    let export: ExportCoordinator
    /// The "Derive Look from JPG" flow and its scratch-until-saved result.
    let derive = DeriveCoordinator()
    /// The active-document global Look export flow. It snapshots edits and never mutates them while
    /// the user reviews omissions or chooses a destination.
    let lookSave = LookSaveCoordinator()

    // Convenience passthroughs so views and the menu don't have to know which
    // collaborator owns a given piece of state.
    var isExporting: Bool { export.isExporting }
    var isBatchExporting: Bool { export.isExporting && export.batchTotal > 0 }
    var batchProgress: Double { export.batchProgress }
    var batchCompleted: Int { export.batchCompleted }
    var batchTotal: Int { export.batchTotal }
    var batchCurrentItem: String? { export.batchCurrentItem }

    func cancelExport() {
        export.cancelBatchExport()
    }

    /// The renderer. An `any RenderEngining` rather than the concrete actor so a test can drive the
    /// preview flow without a GPU — the reason Step 4 introduced the protocol.
    private let engine: any RenderEngining
    private let preferences: UserDefaults
    private let previewCoordinator: PreviewCoordinator
    private struct SourceLoadRequest: Sendable {
        let name: String
        let source: ImageSource
        let sourceReference: EditSourceReference
        let assetID: PhotoAssetID
        let sourceRevision: UInt64
        let editSessionRevision: UInt64
        let hadInMemorySession: Bool
        let traceQuality: String
    }
    /// One non-cancellable source preparation is allowed to run. New navigation replaces this one
    /// pending value, so a burst cannot build a queue of obsolete RAW decoder operations.
    private var pendingSourceLoad: SourceLoadRequest?
    private var loadTask: Task<Void, Never>?
    private let adjacentPreviewPrefetchJobID = ImageWorkScheduler.JobID("adjacent-preview-prefetch")
    private let comparisonPreviewJobID = ImageWorkScheduler.JobID("comparison-preview")
    private let histogramJobID = ImageWorkScheduler.JobID("histogram")
    private var metadataTask: Task<Void, Never>?
    private var prefetchDelayTask: Task<Void, Never>?
    private var previewDebounceTask: Task<Void, Never>?
    private var cancellables: [AnyCancellable] = []
    private let mediaVolumeProvider: any MediaVolumeProviding
    private var mediaVolumeDiscoveryTask: Task<Void, Never>?
    private var mediaVolumeScanTask: Task<Void, Never>?
    private var mediaVolumeImportTask: Task<Void, Never>?

    /// Changes whenever a Look thumbnail's source or edit recipe can change. Look rows use this as
    /// their task identity so a source switch or restored per-photo document refreshes thumbnails
    /// even when the library itself did not change.
    var lookPreviewRevision: UInt64 { sourceRevision &* 31 &+ documentRevision }

    func lookPreview(for look: CubeLUT) async -> CGImage? {
        await lookPreviewCoordinator.image(source: imageSource, document: document, look: look)
    }

    // MARK: - Init

    public convenience init() {
        self.init(engine: RenderEngine.shared, editStore: EditDocumentStore(), includeBundledLooks: false)
    }

    /// Production entry points opt into the packaged starter library. The plain initializer stays
    /// bundle-free for headless/test clients that intentionally provide their own Look folder.
    public convenience init(includeBundledLooks: Bool) {
        self.init(engine: RenderEngine.shared, editStore: EditDocumentStore(), includeBundledLooks: includeBundledLooks)
    }

    init(
        engine: any RenderEngining = RenderEngine.shared,
        editStore: EditDocumentStore = EditDocumentStore(),
        preferences: UserDefaults = .standard,
        mediaVolumeProvider: any MediaVolumeProviding = MountedMediaVolumeProvider(),
        includeBundledLooks: Bool = false
    ) {
        var interval = LumoSignpostInterval(.launch, context: .unknown)
        defer { interval.end() }

        self.engine = engine
        self.preferences = preferences
        self.editStore = editStore
        self.settings = LumoSettings(preferences: preferences)
        self.workScheduler = ImageWorkScheduler()
        // Look thumbnails have a bounded, independent thumbnail lane. Sharing the editor's lane
        // would let a burst of filmstrip/grid work evict a row's continuation before it can return.
        self.lookPreviewCoordinator = LookPreviewCoordinator(
            engine: engine, scheduler: ImageWorkScheduler()
        )
        self.collection = ImageCollection(scheduler: workScheduler, defaults: preferences)
        self.library = LUTLibrary(
            preferences: preferences,
            userLookFolderURL: settings.ensureUserLookFolder(),
            includeBundled: includeBundledLooks
        )
        self.export = ExportCoordinator(engine: engine, editStore: editStore)
        self.previewCoordinator = PreviewCoordinator(engine: engine, scheduler: workScheduler)
        self.mediaVolumeProvider = mediaVolumeProvider

        // A missing value is the first-launch state: single-photo editing is the primary surface.
        // Read this after all stored properties are initialized because the published property's
        // observer persists later user changes through `preferences`.
        if let storedMode = preferences.object(forKey: Self.comparisonModeKey) as? Bool {
            self.isSideBySide = storedMode
        }

        // A Core Image graph is lazy: a publication can be accepted while its drawable command
        // buffer is still able to fail. Keep the previous surface image in that case and surface a
        // useful status instead of leaving the user with a permanent black canvas.
        previewSurface.onPresentationFailure = { [weak self] in
            guard let self, self.sourceImage != nil else { return }
            self.previewState = .failed
            self.autoAdjustmentState = .unavailable("Auto is unavailable because the photo preview failed.")
            self.statusMessage = "Could not display \(self.sourceName). Try Fit or reload the photo."
        }
        originalPreviewSurface.onPresentationFailure = { [weak self] in
            guard let self, self.sourceImage != nil else { return }
            self.statusMessage = "Could not display the comparison preview. Try Fit or reload the photo."
        }

        // Forward nested ObservableObject changes so SwiftUI views update.
        for child in [
            settings.objectWillChange.eraseToAnyPublisher(),
            library.objectWillChange.eraseToAnyPublisher(),
            collection.objectWillChange.eraseToAnyPublisher(),
            export.objectWillChange.eraseToAnyPublisher(),
            derive.objectWillChange.eraseToAnyPublisher(),
            lookSave.objectWillChange.eraseToAnyPublisher(),
        ] {
            cancellables.append(child.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            })
        }

        // Inspector chrome is observed by its own view subtree. Histogram work still belongs to
        // this model, so react after the published state has been assigned without forwarding the
        // inspector publisher through AppViewModel's broad objectWillChange stream.
        cancellables.append(inspectorState.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.inspectorState.isPresented, self.inspectorState.tab == .info {
                    self.updateHistogram()
                } else {
                    self.cancelHistogram(clear: true)
                }
            }
        })

        previewCoordinator.onPublication = { [weak self] publication in
            self?.publishPreview(publication)
        }
        previewCoordinator.onFailure = { [weak self] request in
            guard request.quality == .preview else { return }
            guard let self, request.source == self.imageSource else { return }
            self.previewState = .failed
            self.autoAdjustmentState = .unavailable("Auto is unavailable because the photo preview failed.")
            self.statusMessage = "Could not render \(self.sourceName)"
        }

        wireCoordinators()
        library.restoreFolder()

        // Restore a previously-chosen source folder and open its first image.
        // Both the LUT scan above and this one run asynchronously, so the
        // window paints immediately and fills in as the scans land.
        if collection.restoreSourceFolder() {
            isSourceBrowserPresented = true
            navigation.move(to: .grid)
            collection.beginThumbnailDemand()
            openFirstImageWhenScanned()
        }
    }

    private static let comparisonModeKey = "Lumo.editor.comparisonMode.sideBySide"

    /// Point the coordinators' status/error output at this view model, which
    /// owns the status bar and the alert. They report *what* happened; deciding
    /// how to show it stays here.
    private func wireCoordinators() {
        // Export resolves each selected asset's durable document on demand. The LUT table is not
        // part of that Codable record, so resolve its stable ID against the current Look library
        // only after the store has supplied the per-photo document.
        export.lutResolver = { [weak self] id in self?.resolvedLUT(id) }

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

        library.onImported = { [weak self] lut in
            // Importing is also an audition action when an image is open. With no active image the
            // file still appears in the browser, but must not become a document default that could
            // accidentally leak into a later per-photo session.
            guard let self, self.sourceImage != nil else { return }
            self.selectLook(lut)
        }
        library.onImportError = { [weak self] message in
            self?.presentError(message)
        }

        export.onStatus = { [weak self] in self?.statusMessage = $0 }
        export.onError = { [weak self] in self?.presentError($0) }
        export.defaultFolderURL = { [weak self] in self?.settings.defaultExportFolderURL }

        derive.onStatus = { [weak self] in self?.statusMessage = $0 }
        derive.onError = { [weak self] in self?.presentError($0) }
        derive.onDerived = { [weak self] lut in
            // Preview the new look immediately, if there's something to see.
            guard let self, self.sourceImage != nil else { return }
            self.selectLook(lut)
        }
        derive.libraryFolder = { [weak self] in
            self?.library.folderURL
        }
        derive.canonicalLibraryFolder = { [weak self] in self?.settings.userLookFolderURL }
        derive.onSaved = { [weak self] destination in
            guard let self else { return }
            self.adoptSavedLUT(at: destination)
            // Re-scan so the new entry appears in the sidebar.
            if let folder = self.library.folderURL {
                self.library.scan(folder)
            } else {
                // A clean profile saves into the canonical user Look folder before any external
                // folder is selected. Importing here keeps that saved user Look discoverable.
                self.library.importLUT(from: destination, audition: false)
            }
        }

        lookSave.onStatus = { [weak self] in self?.statusMessage = $0 }
        lookSave.onError = { [weak self] in self?.presentError($0) }
        lookSave.libraryFolder = { [weak self] in
            self?.library.folderURL
        }
        lookSave.canonicalLibraryFolder = { [weak self] in self?.settings.userLookFolderURL }
        lookSave.onSaved = { [weak self] destination in
            // Registration is intentionally non-auditioning. Saving a Look must not add a new
            // edit or undo entry to the photo whose document was exported.
            self?.library.importLUT(from: destination, audition: false)
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
            // Folder open starts in Library even though the first image is also loaded so the
            // editor is ready for an immediate Enter/double-click handoff.
            load(name: first.displayName, url: fileURL, data: nil, assetID: first.id)
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

    // MARK: - Auto adjustment

    /// Whether the one-click action has a settled source render to analyze. The transparent source
    /// marker installed during preparation is deliberately not enough: Auto becomes available only
    /// after a real frame has made it through the presentation lifecycle.
    var canRunAutoAdjustment: Bool {
        sourceImage != nil && imageSource != nil && lastPresentedVisibleRequest != nil
            && previewState == .ready && autoAdjustmentState != .analyzing
    }

    var isAutoAdjustmentInProgress: Bool {
        if case .analyzing = autoAdjustmentState { return true }
        return false
    }

    var autoAdjustmentHelp: String {
        if canRunAutoAdjustment || isAutoAdjustmentInProgress {
            return autoAdjustmentState.message
        }
        if previewState == .failed {
            return "Auto is unavailable because the photo preview failed. Reload the photo to try again."
        }
        if sourceImage == nil || imageSource == nil {
            return "Open a supported photo to enable Auto."
        }
        return "Auto is available when the photo preview is ready."
    }

    /// Analyze the current source, then replace only global Light and global Color values. The
    /// result enters `updateDocument`, so it receives normal per-photo persistence and one undo
    /// operation. RAW/develop, legacy nodes, Looks, Effects, crop, mixer, and grading are retained.
    func runAutoAdjustment() {
        guard canRunAutoAdjustment, let imageSource else { return }
        endUndoGrouping()

        let sourceRevision = self.sourceRevision
        let documentRevision = self.documentRevision
        var analysisDocument = document
        analysisDocument.light = .neutral
        analysisDocument.color.vibrance = 0
        analysisDocument.color.saturation = 0
        // Do not compensate for an existing Look. Auto is a source baseline; applying it also
        // preserves the active Look on the document below.
        analysisDocument.lut = .none
        let engine = self.engine
        autoAdjustmentState = .analyzing
        statusMessage = "Analyzing \(sourceName) for Auto adjustments…"
        autoAdjustmentTask?.cancel()
        autoAdjustmentTask = Task { @MainActor [weak self, engine] in
            let histogram = await engine.histogram(
                source: imageSource,
                document: analysisDocument,
                lut: nil,
                scale: .preview(maxSize: CGSize(width: 1600, height: 1200)),
                space: .current,
                maxDimension: AutoAdjustmentSettings.default.histogramMaxDimension
            )

            guard !Task.isCancelled, let self else { return }
            guard self.sourceRevision == sourceRevision,
                  self.documentRevision == documentRevision,
                  self.imageSource == imageSource else {
                self.autoAdjustmentState = .ready
                return
            }
            guard let histogram,
                  let result = AutoAdjustmentAnalyzer.analyze(histogram: histogram) else {
                let message = "Auto could not analyze \(self.sourceName). Try reloading the photo."
                self.autoAdjustmentState = .failed(message)
                self.statusMessage = message
                return
            }

            self.updateDocument { document in
                document.light = result.light
                document.color.vibrance = result.color.vibrance
                document.color.saturation = result.color.saturation
            }
            self.autoAdjustmentState = .ready
            self.statusMessage = "Auto applied — Light and Color baseline (undo to restore previous edits)"
        }
    }

    private func cancelAutoAdjustment() {
        autoAdjustmentTask?.cancel()
        autoAdjustmentTask = nil
        autoAdjustmentState = .unavailable("Auto is available when the photo preview is ready.")
    }

    // MARK: - Image loading

    func openImage(url: URL) {
        navigation.move(to: .edit)
        load(name: url.lastPathComponent, url: url, data: nil)
    }

    private func openImage(url: URL, assetID: PhotoAssetID) {
        navigation.move(to: .edit)
        load(name: url.lastPathComponent, url: url, data: nil, assetID: assetID)
    }

    /// Prepare a source without decoding pixels, then publish it and render the previews. RAW
    /// demosaicing remains renderer-owned and happens at the requested preview scale. The worker
    /// below deliberately has one active preparation and one replaceable pending request.
    private func load(
        name: String, url: URL?, data: Data?, assetID: PhotoAssetID? = nil,
        traceQuality: String = "open"
    ) {
        let assetID = assetID ?? (url.map(PhotoAssetID.file) ?? data.map(PhotoAssetID.data) ?? .data(Data()))
        endUndoGrouping()
        cancelAutoAdjustment()
        // Discrete edits are queued normally; switching sources is a durability boundary for them.
        // Do not rewrite an unchanged document merely because navigation occurred.
        requestPersistenceFlush()
        activeAssetID = assetID
        let sourceReference = EditSourceReference(assetID: assetID, url: url)
        activeSourceReference = sourceReference
        let session = editSessions[assetID]
        document = session?.document ?? EditDocument()
        activeHistory = session?.history ?? EditHistory()
        lastReportedMissingLUT = nil
        lutResolutionStatus = nil
        refreshLUTResolutionStatus()

        sourceRevision &+= 1
        comparisonRevision &+= 1
        displayRevision &+= 1
        cancelHistogram(clear: true, pump: false)
        let sourceRevision = self.sourceRevision
        previewCoordinator.cancel()
        previewSurface.clear()
        originalPreviewSurface.clear()
        canvasState.resetForSource()
        resetResolutionPlanners()
        // Do not let the previous surface briefly show the photo we are leaving while the new
        // source is being decoded.
        sourceImage = nil
        previewState = .loading
        // The old source must not describe the empty/loading state or gate the new image's
        // inspector while its pixels are being decoded.
        imageSource = nil
        lastPresentedVisibleRequest = nil
        lastPublishedVisibleRequest = nil
        sourceURL = nil
        sourceSize = .zero
        isPreviewInteractionActive = false
        // Space comparison is transient and belongs to the source being left. The user's
        // single-vs-side-by-side preference intentionally remains intact across photo switches.
        isShowingOriginal = false
        metadataTask?.cancel()
        metadata = ImageMetadata()
        cancelComparisonPreview(pump: false)
        workScheduler.cancel(id: adjacentPreviewPrefetchJobID, pump: false)
        prefetchDelayTask?.cancel()
        prefetchDelayTask = nil
        previewDebounceTask?.cancel()
        capabilitiesTask?.cancel()
        rawCapabilities = nil
        capabilitiesProbeCompleted = false
        // A pending develop flag describes the image being left; it must not survive onto whatever
        // opens next, or an unrelated first edit on the new image would render a comparison baseline
        // for develop settings that were never actually touched on it.
        pendingDevelopChange = false
        // Keep the tab during the transient no-source interval. The new source publication below
        // validates it once its actual capabilities are known; resetting here would make an import
        // change an unrelated inspector preference merely because source preparation is async.

        isLoading = true
        statusMessage = "Loading \(name)..."

        let source: ImageSource
        if let url {
            source = ImageSource(url: url, nativeExtent: .zero)
        } else if let data {
            source = ImageSource(data: data, nativeExtent: .zero)
        } else {
            source = ImageSource(backing: .data(Data()), kind: .standard, nativeExtent: .zero)
        }
        pendingSourceLoad = SourceLoadRequest(
            name: name, source: source, sourceReference: sourceReference, assetID: assetID,
            sourceRevision: sourceRevision,
            editSessionRevision: editSessionRevisions[assetID] ?? 0,
            hadInMemorySession: session != nil,
            traceQuality: traceQuality
        )
        startSourceLoadWorkerIfNeeded()
    }

    private func startSourceLoadWorkerIfNeeded() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            while let self, let request = self.pendingSourceLoad {
                self.pendingSourceLoad = nil
                await self.prepareAndInstall(request)
            }
            self?.loadTask = nil
        }
    }

    private func prepareAndInstall(
        _ request: SourceLoadRequest
    ) async {
        var interval = LumoSignpostInterval(
            .photoSwitch,
            context: LumoTraceContext(sourceFingerprint: request.name, quality: request.traceQuality)
        )
        defer { interval.end() }

        // The edit lookup is independent of source preparation. Starting it first lets its actor
        // work overlap a RAW geometry/session probe without putting it on the source-critical path.
        let storedTask = Task { await self.editStore.load(for: request.sourceReference) }
        let preparation = await engine.prepareSource(request.source)

        guard request.sourceRevision == sourceRevision else {
            // Do not publish an obsolete source or its error. The worker will consume only the
            // newest pending request after this single in-flight preparation completes.
            storedTask.cancel()
            return
        }

        guard let preparation else {
            isLoading = false
            previewState = .failed
            presentError("Error: Cannot load \(request.name)")
            storedTask.cancel()
            return
        }

        install(preparation: preparation, request: request)

        let stored = await storedTask.value
        guard request.sourceRevision == sourceRevision else { return }
        adoptStoredEdits(stored, for: request)
    }

    private func install(
        preparation: ImageSourcePreparation, request: SourceLoadRequest
    ) {
        imageSource = preparation.source
        if case .url(let url) = request.source.backing {
            sourceURL = url
        } else {
            sourceURL = nil
        }
        sourceName = request.name
        sourceSize = preparation.nativeExtent
        // This marker is availability state only. It is never sent to RenderEngine, histogram, or
        // detail assessment; the authoritative color-managed pixels come from the edited render.
        sourceImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(
            to: CGRect(origin: .zero, size: preparation.nativeExtent)
        )
        previewState = .loading
        statusMessage = "\(request.name)  \(Int(preparation.nativeExtent.width))\u{00D7}\(Int(preparation.nativeExtent.height))"
        isLoading = false
        keepInspectorTabValid()
        schedulePreview()
        switch request.source.backing {
        case .url(let url): refreshMetadata(url: url, data: nil)
        case .data(let data): refreshMetadata(url: nil, data: data)
        }
        refreshCapabilities()
        scheduleAdjacentPreviewPrefetch()
    }

    private func adoptStoredEdits(
        _ stored: EditDocumentLoadResult, for request: SourceLoadRequest
    ) {
        // A pre-existing session or a mutation made while preparation was in flight owns the
        // current document. Only a still-pristine, never-seen session may adopt disk state.
        let changedInMemory = (editSessionRevisions[request.assetID] ?? 0) != request.editSessionRevision
        let shouldAdopt = !request.hadInMemorySession && !changedInMemory
        if shouldAdopt {
            activeHistory = EditHistory()
            document = stored.document
            editSessions[request.assetID] = PhotoEditSession(document: document, history: activeHistory)
            refreshLUTResolutionStatus()
            documentRevision &+= 1
            comparisonRevision &+= 1
            schedulePreview()
            scheduleAdjacentPreviewPrefetch()
        }
        if stored.status.isActionable {
            editStoreStatus = stored.status.message
        } else {
            editStoreStatus = nil
        }
    }

    /// Warm at most the two nearest filtered neighbours after the active render has had an idle
    /// window. The request is cancellable at the orchestration layer and the snapshot is value-only;
    /// an obsolete prefetch may finish in the renderer, but it cannot publish or start source-load
    /// work for a photo the user has already left.
    private func scheduleAdjacentPreviewPrefetch() {
        workScheduler.cancel(id: adjacentPreviewPrefetchJobID)
        prefetchDelayTask?.cancel()
        prefetchDelayTask = nil
        guard collection.isActive else { return }

        let selected = collection.selectedIndex
        let candidates = collection.filteredIndices
            .filter { $0 != selected && abs($0 - selected) <= 2 }
            .sorted { abs($0 - selected) < abs($1 - selected) }
            .prefix(2)
            .compactMap { index -> (ImageSource, EditDocument, CubeLUT?)? in
                let item = collection.items[index]
                guard let dimensions = item.asset.dimensions,
                      dimensions.width > 0, dimensions.height > 0 else { return nil }
                let extent = CGSize(width: dimensions.width, height: dimensions.height)
                let source: ImageSource
                if let url = item.url {
                    source = ImageSource(url: url, nativeExtent: extent)
                } else if let data = item.imageData {
                    source = ImageSource(data: data, nativeExtent: extent)
                } else {
                    return nil
                }
                let document = editSessions[item.id]?.document ?? EditDocument()
                return (source, document, resolvedLUT(document.lut.lutID))
            }
        guard !candidates.isEmpty else { return }

        let revision = sourceRevision
        let engine = self.engine
        prefetchDelayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, self.sourceRevision == revision else { return }
            self.workScheduler.enqueue(
                id: self.adjacentPreviewPrefetchJobID, lane: .editor, priority: .background
            ) { [weak self, engine] in
                guard !Task.isCancelled, let self, self.sourceRevision == revision else { return }
                for (source, document, lut) in candidates {
                    guard !Task.isCancelled, self.sourceRevision == revision else { return }
                    let request = RenderRequest(
                        source: source, document: document, lut: lut,
                        targetSize: self.previewBackingSize,
                        quality: .preview, output: .raster, space: .current
                    )
                    _ = try? await engine.render(request)
                }
            }
        }
    }

    func openImageDialog() {
        let panel = NSOpenPanel()
        panel.title = "Open Image"
        panel.allowedContentTypes = ImageDecoder.supportedTypes
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.defaultSourceFolderURL

        if panel.runModal() == .OK, let url = panel.url {
            collection.clear()
            openImage(url: url)
        }
    }

    // MARK: - Photo import

    func openImage(data: Data, name: String) {
        navigation.move(to: .edit)
        load(name: name, url: nil, data: data)
    }

    func importFromPhotos() {
        isPhotosPickerPresented = true
    }

    func beginPhotosImport(totalCount: Int) {
        didPresentInspectorForPhotosImport = false
        collection.beginDataImport(reservedCount: max(0, totalCount))
        photosImportProgress = PhotosImportProgress(
            total: max(0, totalCount), processed: 0, imported: 0, failed: 0,
            currentName: nil, phase: .transferring
        )
        statusMessage = "Importing Photos 0/\(max(0, totalCount))…"
    }

    func updatePhotosImportPhase(_ phase: PhotosImportProgress.Phase, name: String) {
        guard var progress = photosImportProgress else { return }
        progress.phase = phase
        progress.currentName = name
        photosImportProgress = progress
        statusMessage = "\(phase.label) \(name)  \(progress.processed)/\(progress.total)…"
    }

    /// Append one transferred item and open the first successful item immediately. The payload is
    /// moved into the collection's source record; no batch array is retained by this method.
    func appendPhotosImport(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) {
        guard var progress = photosImportProgress else { return }
        updatePhotosImportPhase(.inserting, name: item.name)
        let assetID = collection.appendDataImport(item, ordinal: ordinal)
        progress.processed += 1
        progress.imported += 1
        progress.currentName = item.name
        progress.phase = .transferring
        photosImportProgress = progress
        statusMessage = "Imported \(progress.processed)/\(progress.total)  \(item.name)…"

        if collection.importedDataCount == 1 {
            load(name: item.name, url: nil, data: item.data, assetID: assetID,
                 traceQuality: "photosImport")
            presentInspectorForFirstPhotosImportItem()
        }
    }

    /// Present the existing inspector exactly once for the first accepted Photos payload. The
    /// selected tab belongs to the user's inspector preferences, so opening the panel must not
    /// force Info or disturb it; `load()` has already cleared metadata and histogram state for the
    /// new active source before this presentation change is published.
    private func presentInspectorForFirstPhotosImportItem() {
        guard !didPresentInspectorForPhotosImport else { return }
        didPresentInspectorForPhotosImport = true
        guard !inspectorState.isPresented else { return }
        inspectorState.isPresented = true
    }

    func recordPhotosImportFailure(name: String, ordinal: Int? = nil) {
        guard var progress = photosImportProgress else { return }
        if let ordinal {
            collection.recordDataImportFailure(ordinal: ordinal, name: name)
        } else {
            collection.recordDataImportFailure(name: name)
        }
        progress.processed += 1
        progress.failed += 1
        progress.currentName = name
        progress.phase = .transferring
        photosImportProgress = progress
        statusMessage = "Skipped \(name)  \(progress.processed)/\(progress.total)…"
    }

    func finishPhotosImport(cancelled: Bool) {
        collection.finishDataImport()
        guard let progress = photosImportProgress else { return }
        let suffix = progress.failed == 0 ? "" : ", \(progress.failed) skipped"
        statusMessage = cancelled
            ? "Photos import cancelled — \(progress.imported) imported\(suffix)"
            : "Photos import complete — \(progress.imported) imported\(suffix)"
        photosImportProgress = nil
    }

    func importPhotosData(_ items: [(name: String, data: Data)]) {
        collection.addFromData(items)
        if let first = items.first, let assetID = collection.items.first?.id {
            load(name: first.name, url: nil, data: first.data, assetID: assetID)
        }
    }

    // MARK: - Removable media import

    var selectedRemovableMediaFiles: [MediaVolumeFile] {
        removableMediaFiles.filter { removableMediaSelection.contains($0) }
    }

    /// Refresh the menu's volume names. Discovery is intentionally asynchronous: probing a slow
    /// card must never block the editor window or make an empty menu look like a hardware failure.
    func refreshRemovableMedia() {
        mediaVolumeDiscoveryTask?.cancel()
        let provider = mediaVolumeProvider
        mediaVolumeDiscoveryTask = Task { [weak self] in
            let volumes = await provider.discover()
            guard !Task.isCancelled, let self else { return }
            self.removableMediaVolumes = volumes
        }
    }

    /// The File-menu action opens the first discovered volume. The toolbar Import menu exposes
    /// every volume by name when more than one is mounted.
    func importFromRemovableMedia() {
        mediaVolumeDiscoveryTask?.cancel()
        let provider = mediaVolumeProvider
        mediaVolumeDiscoveryTask = Task { [weak self] in
            let volumes = await provider.discover()
            guard !Task.isCancelled, let self else { return }
            self.removableMediaVolumes = volumes
            guard let volume = volumes.first else {
                self.statusMessage = "No supported removable media is mounted"
                return
            }
            self.openRemovableMedia(volume)
        }
    }

    func openRemovableMedia(_ volume: MediaVolume) {
        mediaVolumeScanTask?.cancel()
        mediaVolumeImportTask?.cancel()
        removableMediaVolume = volume
        removableMediaFiles = []
        removableMediaWarnings = []
        removableMediaSelection.clear()
        removableMediaImportProgress = nil
        isRemovableMediaScanning = true
        isRemovableMediaSelectorPresented = true

        let provider = mediaVolumeProvider
        mediaVolumeScanTask = Task { [weak self] in
            do {
                let result = try await provider.scan(volume)
                guard !Task.isCancelled, let self else { return }
                self.removableMediaFiles = result.files
                self.removableMediaWarnings = result.warnings
                self.removableMediaSelection.selectAll(in: result.files)
                self.isRemovableMediaScanning = false
                if result.files.isEmpty {
                    self.removableMediaWarnings.append("No supported images were found on this volume.")
                }
            } catch is CancellationError {
                // Closing the sheet is a normal, recoverable cancellation.
            } catch {
                guard let self else { return }
                if case .permissionDenied = error as? MediaVolumeError,
                   provider.supportsInteractiveAccessGrant,
                   let grantedVolume = self.requestRemovableMediaAccess(for: volume) {
                    self.removableMediaVolume = grantedVolume
                    self.removableMediaVolumes = self.removableMediaVolumes.map { candidate in
                        candidate.id == volume.id ? grantedVolume : candidate
                    }
                    do {
                        let result = try await provider.scan(grantedVolume)
                        guard !Task.isCancelled else { return }
                        self.publishRemovableMediaScan(result)
                        return
                    } catch is CancellationError {
                        return
                    } catch {
                        self.isRemovableMediaScanning = false
                        self.removableMediaWarnings = [error.localizedDescription]
                        return
                    }
                }
                self.isRemovableMediaScanning = false
                self.removableMediaWarnings = [error.localizedDescription]
            }
        }
    }

    /// Raw mounted-volume URLs are not security-scoped URLs. If the removable-media entitlement
    /// is not enough for a particular volume class, an Open panel supplies the user grant and a
    /// bookmark that the provider resolves for the scan and the later URL-backed import.
    private func requestRemovableMediaAccess(for volume: MediaVolume) -> MediaVolume? {
        let panel = NSOpenPanel()
        panel.title = "Grant Access to \(volume.name)"
        panel.message = "Select the root of \(volume.name) to let Lumo read its images."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = volume.url
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return MediaVolume(
            id: volume.id,
            name: volume.name,
            url: url,
            bookmarkData: PhotoAssetSource.bookmarkData(for: url)
        )
    }

    private func publishRemovableMediaScan(_ result: MediaVolumeScanResult) {
        removableMediaFiles = result.files
        removableMediaWarnings = result.warnings
        removableMediaSelection.selectAll(in: result.files)
        isRemovableMediaScanning = false
        if result.files.isEmpty {
            removableMediaWarnings.append("No supported images were found on this volume.")
        }
    }

    func toggleRemovableMediaSelection(_ file: MediaVolumeFile) {
        removableMediaSelection.toggle(file)
    }

    func selectAllRemovableMedia() {
        removableMediaSelection.selectAll(in: removableMediaFiles)
    }

    func selectNoRemovableMedia() {
        removableMediaSelection.clear()
    }

    func cancelRemovableMediaImport() {
        mediaVolumeScanTask?.cancel()
        mediaVolumeImportTask?.cancel()
        isRemovableMediaScanning = false
        isRemovableMediaSelectorPresented = false
        removableMediaImportProgress = nil
    }

    /// Explicitly add the checked files to Lumo's library. This operation is URL-backed and does
    /// not copy, delete, or modify the source card; the selector makes that destination behavior
    /// visible in its button label and the collection retains security-scoped bookmarks.
    func importSelectedRemovableMedia() {
        guard let volume = removableMediaVolume else { return }
        let selected = selectedRemovableMediaFiles
        guard !selected.isEmpty else {
            statusMessage = "Select at least one image to import"
            return
        }

        mediaVolumeImportTask?.cancel()
        removableMediaImportProgress = MediaVolumeImportProgress(
            total: selected.count, processed: 0, imported: 0, skipped: 0,
            currentName: nil, cancelled: false
        )
        let sourceFiles = selected
        mediaVolumeImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let accessURL = volume.resolvedAccessURL()
            let hasScope = accessURL.startAccessingSecurityScopedResource()
            defer { if hasScope { accessURL.stopAccessingSecurityScopedResource() } }
            var usable: [MediaVolumeFile] = []
            for file in sourceFiles {
                guard !Task.isCancelled else {
                    self.finishRemovableMediaImport(
                        imported: 0, skipped: sourceFiles.count,
                        cancelled: true, total: sourceFiles.count
                    )
                    return
                }
                var progress = self.removableMediaImportProgress ?? MediaVolumeImportProgress(
                    total: sourceFiles.count, processed: 0, imported: 0, skipped: 0,
                    currentName: nil, cancelled: false
                )
                progress.currentName = file.filename
                if FileManager.default.isReadableFile(atPath: file.url.path) {
                    usable.append(file)
                    progress.imported += 1
                } else {
                    progress.skipped += 1
                    self.removableMediaWarnings.append("Skipped \(file.filename): the volume was removed or became unreadable.")
                }
                progress.processed += 1
                self.removableMediaImportProgress = progress
                await Task.yield()
            }

            guard !usable.isEmpty else {
                self.statusMessage = "No selected images could be read from \(volume.name)"
                self.isRemovableMediaSelectorPresented = false
                return
            }

            let ids = self.collection.addFromMediaVolume(volume, files: usable)
            if let first = usable.first, let firstID = ids.first {
                self.isSourceBrowserPresented = false
                self.navigation.move(to: .grid)
                self.load(name: first.filename, url: first.url, data: nil, assetID: firstID,
                          traceQuality: "removableMediaImport")
            }
            let progress = self.removableMediaImportProgress
            self.statusMessage = "Imported \(progress?.imported ?? 0) image\(progress?.imported == 1 ? "" : "s") from \(volume.name)"
            self.isRemovableMediaSelectorPresented = false
        }
    }

    private func finishRemovableMediaImport(
        imported: Int, skipped: Int, cancelled: Bool, total: Int
    ) {
        removableMediaImportProgress = MediaVolumeImportProgress(
            total: total, processed: imported + skipped, imported: imported,
            skipped: skipped, currentName: nil, cancelled: cancelled
        )
        statusMessage = cancelled
            ? "Removable media import cancelled — \(imported) imported, \(skipped) skipped"
            : "Removable media import complete — \(imported) imported, \(skipped) skipped"
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
        panel.directoryURL = settings.defaultSourceFolderURL

        if panel.runModal() == .OK, let url = panel.url {
            openSourceFolder(url: url)
        }
    }

    /// Adopt `url` as the source folder (persisted), reveal the browser, and
    /// open its first image. Shared by the menu/toolbar action and folder drops.
    func openSourceFolder(url: URL) {
        collection.setSourceFolder(url)
        isSourceBrowserPresented = true
        navigation.move(to: .grid)
        collection.beginThumbnailDemand()
        openFirstImageWhenScanned()
    }

    func toggleSourceBrowser() {
        if navigation.isGrid, !navigate(to: .edit) { return }
        isSourceBrowserPresented.toggle()
    }

    func toggleLibraryGrid() {
        navigate(to: navigation.isGrid ? .edit : .grid)
    }

    /// Move between the two top-level workspaces. Entering Edit always uses the collection's active
    /// item, so a grid selection is handed off deterministically and never relies on a stale source
    /// image. The first folder scan is allowed to establish the initial Grid state asynchronously;
    /// user-triggered transitions require an actual active item.
    @discardableResult
    func navigate(to mode: NavigationState.Mode) -> Bool {
        switch mode {
        case .grid:
            guard collection.isActive else { return false }
            navigation.move(to: .grid)
            collection.beginThumbnailDemand()
            return true

        case .edit:
            guard collection.isActive, collection.selectedItem != nil else {
                return sourceImage != nil && setEditMode()
            }
            navigation.move(to: .edit)
            openActiveCollectionImage(loadMode: false)
            return true
        }
    }

    private func setEditMode() -> Bool {
        navigation.move(to: .edit)
        return true
    }

    /// Re-scan the current source folder for added/removed files.
    func refreshSource() {
        collection.refresh()
    }

    func selectCollectionImage(at index: Int, additive: Bool = false) {
        guard collection.items.indices.contains(index) else { return }
        collection.select(at: index, modifiers: additive ? [.command] : [])
        let item = collection.items[index]

        if let url = item.url {
            openImage(url: url, assetID: item.id)
        } else if let data = item.imageData {
            load(name: item.displayName, url: nil, data: data, assetID: item.id)
        }
    }

    // MARK: - Copy and paste

    /// Copy the active photo's value-state edits. RAW decoder defaults are represented by neutral
    /// optional settings, so copying never transfers a source photo's as-shot seed accidentally.
    func copyAllEdits() {
        guard activeAssetID != nil, sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }
        editClipboard = EditClipboardPayload(document: document)
        statusMessage = "Copied all edits from \(sourceName)"
    }

    /// Paste to the active photo, or to every selected photo. Non-active destinations receive their
    /// own history entry and disk snapshot; they do not need to be opened first.
    func pasteEdits() {
        guard let clipboard = editClipboard else {
            statusMessage = "Copy edits first"
            return
        }

        let selected = collection.selectedItems
        if selected.isEmpty {
            guard activeAssetID != nil, let source = imageSource else {
                statusMessage = "Open an image first"
                return
            }
            endUndoGrouping()
            let updated = clipboard.applying(
                to: document, destinationIsRAW: source.kind == .raw
            )
            updateDocument { $0 = updated }
            statusMessage = "Pasted edits"
            return
        }

        endUndoGrouping()
        var pastedCount = 0
        for item in selected {
            let assetID = item.id
            let destinationIsRAW: Bool
            if let url = item.url {
                destinationIsRAW = ImageSource.kind(forExtension: url.pathExtension) == .raw
            } else if let data = item.imageData {
                destinationIsRAW = ImageSource.kind(forData: data) == .raw
            } else {
                destinationIsRAW = false
            }

            if assetID == activeAssetID {
                let updated = clipboard.applying(
                    to: document, destinationIsRAW: destinationIsRAW
                )
                updateDocument { $0 = updated }
            } else {
                var session = editSessions[assetID] ?? PhotoEditSession()
                let updated = clipboard.applying(
                    to: session.document, destinationIsRAW: destinationIsRAW
                )
                guard updated != session.document else { continue }
                session.history.endGrouping(document: session.document)
                session.history.recordChange(from: session.document, to: updated)
                session.document = updated
                editSessions[assetID] = session
                queuePersistence(
                    updated,
                    for: EditSourceReference(assetID: assetID, url: item.url),
                    reportsStatus: false,
                    force: true
                )
            }
            pastedCount += 1
        }

        statusMessage = pastedCount == 1
            ? "Pasted edits to 1 photo"
            : pastedCount > 1 ? "Pasted edits to \(pastedCount) photos" : "Pasted edits"
        requestPersistenceFlush()
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
        openActiveCollectionImage(loadMode: true)
    }

    private func openActiveCollectionImage(loadMode: Bool) {
        guard let item = collection.selectedItem else { return }
        if loadMode { navigation.move(to: .edit) }

        // The library selection is the source of truth for the edit handoff. When returning from
        // the grid, the active item is often already prepared because the editor was left visible
        // behind the library. Reusing that source avoids clearing a valid preview (and the canvas
        // presentation state) just to revisit the same photo. If the surface was recreated or a
        // preview is still pending, explicitly request the visible render again.
        if activeAssetID == item.id {
            if imageSource != nil, sourceImage != nil {
                if previewSurface.image == nil {
                    previewState = .loading
                    schedulePreview()
                }
                return
            }
            // A source preparation can be non-cancellable. Let the in-flight, revision-checked
            // request finish instead of enqueueing a duplicate while the user is navigating.
            if loadTask != nil { return }
        }

        if let url = item.url {
            openImage(url: url, assetID: item.id)
        } else if let data = item.imageData {
            if loadMode { navigation.move(to: .edit) }
            load(name: item.displayName, url: nil, data: data, assetID: item.id)
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

    // MARK: - Look selection

    func selectLook(_ look: CubeLUT?) {
        // A derived LUT is in no library, so nothing but the registry can resolve it later. Remember
        // it rather than replacing the last one: a document made now must still resolve after the
        // user derives again.
        if let look, look.lutID.isDerived { derivedRegistry.register(look) }
        endUndoGrouping()
        updateDocument { $0.lut.lutID = look?.lutID }
        refreshLUTResolutionStatus()
    }

    /// Select a Look by its stable document ID. The browser binds to IDs rather than resolved LUT
    /// values so the explicit None row and a missing file remain distinct selections.
    func selectLook(id: LUTID?) {
        guard let id else {
            selectLook(nil)
            return
        }
        guard let look = resolvedLUT(id) else {
            if library.isScanning {
                statusMessage = "Look is still loading. Try selecting it again when scanning finishes."
            } else {
                // Keep an unresolved persisted ID intact, but make an attempted selection
                // observable and recoverable through the inspector's clear action.
                refreshLUTResolutionStatus()
            }
            return
        }
        selectLook(look)
    }

    /// Historical model-name compatibility for existing integrations and persisted-workflow
    /// tests. New editor code should use the Look-named actions above.
    func selectLUT(_ lut: CubeLUT?) { selectLook(lut) }

    func selectLUT(id: LUTID?) { selectLook(id: id) }

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
        let comparisonChanged = developChanged || updated.crop != document.crop
        displayRevision &+= 1
        cancelHistogram(clear: false, pump: false)
        activeHistory.recordChange(from: document, to: updated)
        document = updated
        if !document.hasVisibleLookEdits { isShowingOriginal = false }
        refreshLUTResolutionStatus()
        saveActiveDocument()
        documentRevision &+= 1
        // Look edits leave the baseline unchanged, so an in-flight baseline remains useful. A RAW
        // develop edit changes the explicit before-image and must invalidate that work; it will be
        // queued again after the new visible result publishes.
        if comparisonChanged {
            comparisonRevision &+= 1
            cancelComparisonPreview(pump: false)
            originalPreviewSurface.clear()
        }
        // OR'd in rather than assigned: a call earlier in a coalesced burst may have changed a
        // comparison-frame stage even though this call did not, and only the last call's task
        // survives to fire (see `pendingDevelopChange`'s doc comment).
        pendingDevelopChange = pendingDevelopChange || comparisonChanged

        guard debounced else {
            previewDebounceTask?.cancel()
            previewDebounceTask = nil
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
        let message = "Look “\(name)” is unavailable; the stored reference was kept."
        lastReportedMissingLUT = id
        lutResolutionStatus = message
        statusMessage = message
    }

    func selectPreviousLook() {
        guard let current = selectedLook,
              let idx = library.allLUTs.firstIndex(of: current),
              idx > 0 else { return }
        selectLook(library.allLUTs[idx - 1])
    }

    func selectNextLook() {
        guard let current = selectedLook else {
            if let first = library.allLUTs.first { selectLook(first) }
            return
        }
        guard let idx = library.allLUTs.firstIndex(of: current),
              idx < library.allLUTs.count - 1 else { return }
        selectLook(library.allLUTs[idx + 1])
    }

    func selectPreviousLUT() { selectPreviousLook() }

    func selectNextLUT() { selectNextLook() }

    /// Reset only the Look stage. Other inspector panels remain untouched, and the operation is one
    /// reversible history entry for the active photo.
    func resetLook() {
        endUndoGrouping()
        updateDocument { $0.lut = .none }
    }

    // MARK: - LUT application

    private func applyLUT() {
        schedulePreview()
    }

    /// Set the LUT strength (0...1) and re-render the preview. Safe to call on
    /// every slider tick: the re-render is debounced and the previous one is
    /// cancelled, so a full-travel drag costs a handful of renders, not one per
    /// pixel of travel.
    func setLookIntensity(_ value: Double) {
        let clamped = max(0, min(1, value))
        guard clamped != document.lut.intensity else { return }
        let oldDocument = document
        displayRevision &+= 1
        cancelHistogram(clear: false, pump: false)
        document.lut.intensity = clamped
        activeHistory.recordChange(from: oldDocument, to: document)
        saveActiveDocument()
        documentRevision &+= 1
        if isPreviewInteractionActive {
            scheduleInteractivePreview()
        } else {
            scheduleSettledPreviewAfterDebounce()
        }
    }

    func setLUTIntensity(_ value: Double) { setLookIntensity(value) }

    // MARK: - Preview

    /// Backing pixels of the visible canvas. PreviewView updates this from its live geometry;
    /// the fallback is only used before the first layout pass.
    private var previewBackingSize = CGSize(width: 1600, height: 1200)
    /// Each logical rendering surface owns its hysteresis state. Main preview settled and
    /// interactive requests share a planner because they describe the same canvas; supporting
    /// surfaces remain independent so a future viewport/crop difference cannot leak detail choices
    /// between them.
    private var mainPreviewResolutionPlanner = ResolutionPlanner()
    private var comparisonResolutionPlanner = ResolutionPlanner()
    private var histogramResolutionPlanner = ResolutionPlanner()
    private static let intensityDebounceMs = 60

    /// Request enough source detail for the current display scale while leaving the final
    /// placement to `PreviewSurfaceView`. The coalescing coordinator keeps a zoom gesture from
    /// building a queue of obsolete high-resolution renders.
    private func previewRenderTargetSize(
        for document: EditDocument,
        surface: ResolutionPlannerSurface = .mainPreview
    ) -> CGSize {
        guard let imageSource else { return previewBackingSize }
        return resolutionPlan(
            for: document,
            nativeExtent: imageSource.nativeExtent,
            viewportSize: previewBackingSize,
            surface: surface
        ).sourceSize
    }

    /// Plan source detail for one logical rendering surface.
    ///
    /// This stays an internal value seam so tests can exercise the same surface routing without
    /// depending on asynchronous image preparation or a real drawable size. Production render
    /// requests use `previewRenderTargetSize(for:surface:)` above.
    func resolutionPlan(
        for document: EditDocument,
        nativeExtent: CGSize,
        viewportSize: CGSize,
        surface: ResolutionPlannerSurface
    ) -> ResolutionPlan {
        switch surface {
        case .mainPreview:
            return mainPreviewResolutionPlanner.plan(
                nativeExtent: nativeExtent,
                crop: document.crop,
                viewportSize: viewportSize,
                navigation: canvasState.navigation
            )
        case .comparisonBaseline:
            return comparisonResolutionPlanner.plan(
                nativeExtent: nativeExtent,
                crop: document.crop,
                viewportSize: viewportSize,
                navigation: canvasState.navigation
            )
        case .histogram:
            return histogramResolutionPlanner.plan(
                nativeExtent: nativeExtent,
                crop: document.crop,
                viewportSize: viewportSize,
                navigation: canvasState.navigation
            )
        }
    }

    private func resetResolutionPlanners() {
        mainPreviewResolutionPlanner.reset()
        comparisonResolutionPlanner.reset()
        histogramResolutionPlanner.reset()
    }

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
        var requested = isShowingOriginal ? document.comparisonBaseline : document

        // Crop is a composition stage. While the tool is open the overlay is expressed in the
        // full, oriented source coordinate space, so the pixels underneath it must be the same
        // adjusted stage before crop. This preserves the developed-source cache (including RAW
        // reuse) while making the saved rectangle line up with recognizable content. Vignette and
        // grain consequently describe this temporary full-source frame; the committed request
        // below restores their existing post-crop semantics.
        if canvasState.isCropToolActive {
            requested.crop = .neutral
        }

        return isShowingOriginal ? (requested, nil) : (requested, selectedLook)
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

        displayRevision &+= 1
        cancelHistogram(clear: false, pump: false)

        let (requested, look) = displayRequest
        previewCoordinator.submit(RenderRequest(
                source: imageSource, document: requested, lut: look,
                targetSize: previewRenderTargetSize(for: requested, surface: .mainPreview), quality: .preview,
                output: .raster, space: .current
            ), phase: .settled, sourceRevision: sourceRevision,
            displayRevision: displayRevision)
    }

    /// A viewport-sized interactive render. `PreviewCoordinator` drops superseded values and
    /// promotes the last value to a normal `.preview` render after the quiet period.
    private func scheduleInteractivePreview() {
        guard let imageSource else { return }
        displayRevision &+= 1
        cancelHistogram(clear: false, pump: false)
        let (requested, lut) = displayRequest
        previewCoordinator.submit(RenderRequest(
            source: imageSource, document: requested, lut: lut,
            targetSize: previewRenderTargetSize(for: requested, surface: .mainPreview), quality: .interactive,
            output: .raster, space: .current
        ), phase: .interactive, sourceRevision: sourceRevision,
        displayRevision: displayRevision)
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

    // MARK: - Crop

    /// Enter the crop tool. The first draft is the committed crop, or the full image when this is a
    /// new crop. Crop interaction uses a fit canvas so screen coordinates map directly to the
    /// oriented source image and are not confused with presentation zoom/pan.
    func beginCrop() {
        guard sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }
        guard !canvasState.isCropToolActive else { return }
        endUndoGrouping()
        isShowingOriginal = false
        canvasState.beginCrop(using: document.crop)
        statusMessage = "Adjust crop, then Apply"
        // The committed preview may already be cropped. Ask for the same adjusted stage without
        // the composition crop so the full-source overlay has actual pixels underneath it.
        schedulePreview()
    }

    func toggleCropTool() {
        if isCropToolActive { cancelCrop() } else { beginCrop() }
    }

    /// Update only the transient framing rectangle. The model clamps it to image bounds and rejects
    /// invalid/degenerate values, so every pointer update remains safe to display.
    func updateCropDraft(_ normalizedRect: CGRect) {
        canvasState.updateCropDraft(normalizedRect)
    }

    /// Select a crop ratio in the transient tool state. The current crop center and approximate
    /// area are preserved, while the resulting frame is clamped to the source image bounds.
    func selectCropAspectRatio(_ aspectRatio: CropAspectRatio) {
        guard sourceSize != .zero else { return }
        canvasState.selectCropAspectRatio(aspectRatio, imageSize: sourceSize)
    }

    /// Commit the current draft as one ordinary document mutation, giving it persistence, undo,
    /// copy/paste, cache invalidation, and preview/export parity automatically.
    func commitCrop() {
        guard canvasState.isCropToolActive else { return }
        let committed = canvasState.cropDraft ?? CropAdjustments.unitRect
        let aspectRatio = canvasState.cropAspectRatio
        canvasState.finishCrop()
        let previousDocument = document
        updateDocument { $0.crop = CropAdjustments(normalizedRect: committed, aspectRatio: aspectRatio) }
        // Applying an unchanged draft is still a composition transition: updateDocument quite
        // correctly records no history entry, but the temporary uncropped preview must be replaced
        // by the committed framing.
        if document == previousDocument {
            schedulePreview()
        }
        statusMessage = "Crop applied"
    }

    /// Abandon the draft and restore the committed framing without adding an undo entry.
    func cancelCrop() {
        guard canvasState.isCropToolActive else { return }
        canvasState.finishCrop()
        // Restore the committed framing without touching history or persistence.
        schedulePreview()
        statusMessage = hasCropAdjustments ? "Crop unchanged" : "Crop cancelled"
    }

    /// While editing, Reset returns the draft to the full image. Outside the tool it clears the
    /// committed crop through the normal history/persistence path.
    func resetCrop() {
        if canvasState.isCropToolActive {
            canvasState.resetCropDraft()
            statusMessage = "Crop reset"
        } else {
            endUndoGrouping()
            updateDocument { $0.crop = .neutral }
        }
    }

    // MARK: - Canvas navigation

    func fitCanvas() {
        canvasState.fit()
        schedulePreview()
    }

    func fillCanvas() {
        canvasState.fill()
        schedulePreview()
    }

    func resetCanvas() {
        canvasState.reset()
        schedulePreview()
    }

    func toggleCanvasZoom() {
        canvasState.toggleFitAndRememberedZoom()
        schedulePreview()
    }

    func setCanvasZoom(_ value: CGFloat) {
        let oldValue = canvasState.navigation.zoom
        canvasState.setZoom(value)
        guard canvasState.navigation.zoom != oldValue else { return }
        displayRevision &+= 1
        cancelHistogram(clear: false, pump: false)
        if isPreviewInteractionActive {
            scheduleInteractivePreview()
        } else {
            scheduleSettledPreviewAfterDebounce()
        }
    }

    func zoomCanvas(by factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        setCanvasZoom(canvasState.navigation.zoom * factor)
    }

    /// Pinch-zoom is presentation-only, unlike a slider drag, so this deliberately does not call
    /// `beginPreviewInteraction`/`endPreviewInteraction`: those also open an undo grouping and
    /// queue a document save, which would flash a "saving" status and grow the undo stack for a
    /// gesture that never touches `document`.
    func beginCanvasInteraction() {
        isPreviewInteractionActive = true
        previewCoordinator.beginInteraction()
    }

    func endCanvasInteraction() {
        isPreviewInteractionActive = false
        previewCoordinator.endInteraction()
    }

    /// Pan is a presentation-only operation. It updates the Metal transform immediately and does
    /// not wait for a new render; zoom is the operation that asks the coordinator for more detail.
    func panCanvas(by delta: CGSize, viewportSize: CGSize) {
        guard let imageSource else { return }
        canvasState.pan(
            by: CGSize(width: delta.width, height: -delta.height),
            imageExtent: CGRect(origin: .zero, size: imageSource.nativeExtent),
            viewportSize: viewportSize
        )
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
        let wasGrouping = activeHistory.isGrouping
        activeHistory.endGrouping(document: document)
        if wasGrouping { saveActiveDocument(force: true) }
    }

    var canUndo: Bool { activeHistory.canUndo }
    var canRedo: Bool { activeHistory.canRedo }
    var undoDepth: Int { activeHistory.undoCount }

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

    /// Reset the currently visible inspector stage without crossing into another stage. The
    /// toolbar uses this alongside each panel's local reset links so the scope is explicit before
    /// the action is taken; every branch still records through the stage's existing undo path.
    func resetInspectorSection() {
        switch inspectorTab {
        case .info:
            statusMessage = "Info has no adjustments to reset"
        case .light:
            resetAllLight()
        case .develop:
            resetAllDevelop()
        case .adjust:
            resetAllAdjustments()
        case .effects:
            resetAllEffects()
        case .look:
            resetLook()
        }
    }

    private func applyHistoryDocument(_ restored: EditDocument) {
        let developChanged = restored.rawDevelop != document.rawDevelop
        let comparisonChanged = developChanged || restored.crop != document.crop
        displayRevision &+= 1
        cancelHistogram(clear: false, pump: false)
        document = restored
        refreshLUTResolutionStatus()
        saveActiveDocument(force: true)
        documentRevision &+= 1
        if comparisonChanged {
            comparisonRevision &+= 1
            cancelComparisonPreview(pump: false)
            originalPreviewSurface.clear()
        }
        pendingDevelopChange = comparisonChanged
        schedulePreview()
    }

    private func publishPreview(_ publication: PreviewCoordinator.Publication) {
        guard publication.sourceRevision == sourceRevision,
              publication.displayRevision == displayRevision,
              publication.request.source == imageSource else { return }
        let request = publication.request
        let detailIdentity = PreviewFrameIdentity(
            sourceToken: request.source.traceToken,
            documentHash: request.document.editHash,
            space: request.space
        )
        let detailFactor = request.renderScale.factor(for: request.source.nativeExtent)
        let presentationConfirmation: (() -> Void)? = publication.phase == .settled
            ? { [weak self] in
                self?.didPresentVisibleFrame(
                    request, sourceRevision: publication.sourceRevision,
                    displayRevision: publication.displayRevision
                )
            }
            : nil
        if let gpuImage = publication.gpuImage {
            previewSurface.present(gpuImage, space: request.space,
                                   revision: publication.revision,
                                   telemetry: previewCoordinator.telemetry,
                                   source: request.source,
                                   quality: request.quality,
                                   detailIdentity: detailIdentity,
                                   detailFactor: detailFactor,
                                   onPresented: presentationConfirmation)
        } else if let cgImage = publication.image {
            // Non-GPU conformers retain a raster compatibility seam, but it terminates at the
            // same persistent surface. Production RenderEngine publishes `gpuImage`, so this does
            // not allocate or publish an NSImage on the normal preview path.
            previewSurface.present(CIImage(cgImage: cgImage), space: request.space,
                                   revision: publication.revision,
                                   telemetry: previewCoordinator.telemetry,
                                   source: request.source,
                                   quality: request.quality,
                                   detailIdentity: detailIdentity,
                                   detailFactor: detailFactor,
                                   onPresented: presentationConfirmation)
        }
        guard publication.gpuImage != nil || publication.image != nil else {
            if publication.phase == .settled {
                previewState = .failed
                autoAdjustmentState = .unavailable("Auto is unavailable because the photo preview failed.")
                statusMessage = "Could not render \(sourceName)"
            }
            return
        }
        if publication.phase == .settled {
            lastPublishedVisibleRequest = request
        }

    }

    /// Supporting work starts only after the persistent presentation surface confirms that the
    /// visible frame made it through its drawable lifecycle. This keeps a completed renderer result
    /// from being mistaken for pixels the user has actually received.
    private func didPresentVisibleFrame(
        _ request: RenderRequest, sourceRevision: UInt64, displayRevision: UInt64
    ) {
        guard sourceRevision == self.sourceRevision,
              displayRevision == self.displayRevision,
              request.source == imageSource else { return }
        previewState = .ready
        if !isAutoAdjustmentInProgress { autoAdjustmentState = .ready }
        lastPresentedVisibleRequest = request
        let needsComparisonRefresh = pendingDevelopChange
        pendingDevelopChange = false
        if isSideBySideVisible || needsComparisonRefresh {
            scheduleOriginalPreview(allowHiddenPreparation: needsComparisonRefresh)
        } else {
            cancelComparisonPreview()
        }
        updateHistogram(for: request)
    }

    /// Rasterize the comparison baseline for the side-by-side left panel. Only needs to re-run when
    /// the image or the develop settings change — not when the look does. A mode-entry request may
    /// start from the current preview candidate before its drawable confirmation arrives; normal
    /// supporting work remains gated on that confirmation below.
    private func scheduleOriginalPreview(
        allowHiddenPreparation: Bool = false,
        allowBeforePresentationConfirmation: Bool = false
    ) {
        let hasCurrentPreviewCandidate = allowBeforePresentationConfirmation
            && previewSurface.image != nil
            && lastPublishedVisibleRequest?.source == imageSource
            && lastPublishedVisibleRequest?.document == document
        guard (lastPresentedVisibleRequest != nil || hasCurrentPreviewCandidate),
              (isSideBySideVisible || allowHiddenPreparation),
              let imageSource else {
            cancelComparisonPreview()
            originalPreviewSurface.clear()
            return
        }
        let baseline = document.comparisonBaseline
        let box = previewRenderTargetSize(for: baseline, surface: .comparisonBaseline)
        let sourceRevision = self.sourceRevision
        let comparisonRevision = self.comparisonRevision

        workScheduler.enqueue(
            id: comparisonPreviewJobID, lane: .editor, priority: .comparison
        ) { [weak self, engine] in
            guard !Task.isCancelled, let self else { return }
            let request = RenderRequest(
                source: imageSource, document: baseline, lut: nil,
                targetSize: box, quality: .preview, output: .raster, space: .current
            )
            let gpuImage = await engine.makeCIImage(request)
            if let gpuImage {
                guard !Task.isCancelled,
                      sourceRevision == self.sourceRevision,
                      comparisonRevision == self.comparisonRevision,
                      self.imageSource == imageSource else { return }
                self.originalPreviewSurface.present(gpuImage, space: request.space)
                return
            }
            let cgImage = await engine.makeCGImage(request)
            guard !Task.isCancelled,
                  sourceRevision == self.sourceRevision,
                  comparisonRevision == self.comparisonRevision,
                  self.imageSource == imageSource,
                  let cgImage else { return }
            self.originalPreviewSurface.present(CIImage(cgImage: cgImage), space: request.space)
        }
    }

    private func cancelComparisonPreview(pump: Bool = true) {
        workScheduler.cancel(id: comparisonPreviewJobID, pump: pump)
    }

    /// Toggle between original and LUT preview (for Space-hold comparison).
    @discardableResult
    func showOriginal(_ show: Bool) -> Bool {
        guard !show || isComparisonAvailable else {
            if isShowingOriginal {
                isShowingOriginal = false
                schedulePreview()
            }
            return false
        }
        guard show != isShowingOriginal else { return true }
        isShowingOriginal = show
        displayRevision &+= 1
        cancelHistogram(clear: false, pump: false)
        schedulePreview()
        return true
    }

    @discardableResult
    func toggleSideBySide() -> Bool {
        // An active retained side-by-side preference must remain dismissible after Reset Photo or
        // when navigation lands on an identity document. Enabling it from single view still uses
        // the meaningful-edit gate, preserving the existing affordance semantics for untouched
        // photos.
        guard isComparisonAvailable || isSideBySideVisible else { return false }
        isSideBySide.toggle()
        if isSideBySide {
            scheduleOriginalPreview(allowBeforePresentationConfirmation: true)
        } else {
            cancelComparisonPreview()
            originalPreviewSurface.clear()
        }
        return true
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
    private func updateHistogram(for displayedRequest: RenderRequest? = nil) {
        // Both halves of the gate: an inspector parked on Develop shows no histogram, so tallying
        // one on every settled render of a slider drag is pure waste.
        guard isInspectorPresented, inspectorTab == .info else {
            cancelHistogram(clear: true)
            return
        }
        guard let imageSource else {
            cancelHistogram(clear: true)
            return
        }
        guard lastPresentedVisibleRequest != nil else { return }
        let request: RenderRequest
        if let displayedRequest {
            request = displayedRequest
        } else {
            let (requested, lut) = displayRequest
            request = RenderRequest(
                source: imageSource, document: requested, lut: lut,
                targetSize: previewRenderTargetSize(for: requested, surface: .histogram), quality: .preview,
                output: .raster, space: .current
            )
        }
        guard request.source == imageSource else {
            cancelHistogram(clear: true)
            return
        }

        let sourceRevision = self.sourceRevision
        let displayRevision = self.displayRevision

        // Opening the Info tab can race the settled publication that is already on its way. Do not
        // tally the same displayed request twice just because both paths noticed it.
        if workScheduler.contains(histogramJobID),
           histogramTaskRevision == displayRevision,
           histogramTaskRequest == request {
            return
        }
        cancelHistogram(clear: false)
        histogramTaskRevision = displayRevision
        histogramTaskRequest = request
        isHistogramLoading = true
        histogramErrorMessage = nil
        workScheduler.enqueue(id: histogramJobID, lane: .editor, priority: .histogram) {
            [weak self, engine] in
            guard !Task.isCancelled, let self else { return }
            let result = await engine.histogram(
                source: request.source, document: request.document, lut: request.lut,
                scale: request.renderScale, space: request.space, maxDimension: 512
            )
            guard !Task.isCancelled,
                  self.isInspectorPresented,
                  self.inspectorTab == .info,
                  sourceRevision == self.sourceRevision,
                  displayRevision == self.displayRevision,
                  self.imageSource == request.source else { return }
            self.histogram = result
            self.isHistogramLoading = false
            if result == nil {
                let message = "Histogram unavailable for \(self.sourceName)."
                self.histogramErrorMessage = message
                self.statusMessage = message
            } else {
                self.histogramErrorMessage = nil
            }
        }
    }

    /// Cancel pending or in-flight histogram work. The revision check in the task remains necessary:
    /// a renderer may be finishing a non-cancellable Core Image operation after its task is canceled.
    private func cancelHistogram(clear: Bool, pump: Bool = true) {
        workScheduler.cancel(id: histogramJobID, pump: pump)
        histogramTaskRevision = nil
        histogramTaskRequest = nil
        if isHistogramLoading { isHistogramLoading = false }
        if histogramErrorMessage != nil { histogramErrorMessage = nil }
        if clear { histogram = nil }
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
        capabilitiesProbeCompleted = false

        guard let imageSource else {
            capabilitiesProbeCompleted = true
            keepInspectorTabValid()
            return
        }
        let revision = sourceRevision
        capabilitiesTask = Task { [engine] in
            let capabilities = await engine.rawCapabilities(for: imageSource)
            guard !Task.isCancelled,
                  revision == self.sourceRevision,
                  self.imageSource == imageSource else { return }
            self.rawCapabilities = capabilities
            self.capabilitiesProbeCompleted = true
            self.keepInspectorTabValid()
        }
    }

    /// Keep the Picker selection valid as source publication and capability probing change which
    /// tabs exist. The base Info tab is always available for a loaded image.
    private func keepInspectorTabValid() {
        let tabs = availableInspectorTabs
        guard let fallback = tabs.first else {
            if inspectorTab != .info { inspectorTab = .info }
            return
        }
        if !tabs.contains(inspectorTab) {
            inspectorTab = fallback
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
            lut: selectedLook,
            baseName: ExportCoordinator.exportBaseName(source: base, lut: selectedLook)
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

    /// Export exactly the library selection. The active photo is not implicitly added when the
    /// user has selected other cells; selection and edit focus are separate in the grid model.
    func exportSelectedDialog() {
        let request = selectedBatchExportRequest
        guard !request.items.isEmpty else {
            statusMessage = "Select at least one photo to export"
            return
        }
        export.batchExportDialog(items: request.items, document: request.document, lut: request.lut)
    }

    /// What Export All would write, without running a panel. Internal for the same reason
    /// `exportRequest` is.
    var batchExportRequest: (items: [ExportCoordinator.BatchItem], document: EditDocument, lut: CubeLUT?) {
        makeBatchExportRequest(from: collection.items)
    }

    /// The panel-free request used by Export Selected. Unlike the historical `batchExportRequest`
    /// compatibility seam, this list is never widened to the whole collection.
    var selectedBatchExportRequest: (items: [ExportCoordinator.BatchItem], document: EditDocument, lut: CubeLUT?) {
        makeBatchExportRequest(from: collection.selectedItems)
    }

    /// Alternate spelling for callers that use the product-facing command name.
    var selectedExportRequest: (items: [ExportCoordinator.BatchItem], document: EditDocument, lut: CubeLUT?) {
        selectedBatchExportRequest
    }

    private func makeBatchExportRequest(
        from sourceItems: [ImageCollection.Item]
    ) -> (items: [ExportCoordinator.BatchItem], document: EditDocument, lut: CubeLUT?) {
        // Snapshot only Sendable source/edit values — never carry NSImage thumbnails into export.
        // A missing session document is intentional: ExportCoordinator asks EditDocumentStore for
        // the durable record, so unopened selected photos still export their own saved edits.
        let items = sourceItems.map { item in
            let itemDocument: EditDocument?
            if item.id == activeAssetID {
                itemDocument = document
            } else {
                itemDocument = editSessions[item.id]?.document
            }
            let itemLUT = itemDocument.flatMap { resolvedLUT($0.lut.lutID) }
            return ExportCoordinator.BatchItem(
                url: item.url,
                data: item.imageData,
                name: item.displayName,
                assetID: item.id,
                bookmarkData: item.asset.bookmarkData,
                document: itemDocument,
                lut: itemLUT
            )
        }
        return (items: items, document: document, lut: selectedLook)
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

    /// Present the support-matrix confirmation for the active photo's LUT-compatible edits.
    func presentSaveLook() {
        guard sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }
        let suggested: String
        if let sourceURL {
            suggested = sourceURL.deletingPathExtension().lastPathComponent + " Look"
        } else {
            suggested = "Look"
        }
        lookSave.present(document: document, lut: selectedLook, suggestedName: suggested)
    }

    func dismissSaveLook() {
        lookSave.dismiss()
    }

    func saveLook() {
        lookSave.saveDialog()
    }

    // MARK: - Look folder

    func chooseLookFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Look Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            library.setFolder(url)
        }
    }

    /// Import one or more external `.cube`/text-based `.look` files from ordinary Finder locations.
    /// The library owns parsing, security-scoped access, and persistence; this method only owns the
    /// AppKit panel and the user-facing entry point.
    func chooseLookFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Look"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "cube"),
            UTType(filenameExtension: "look"),
        ].compactMap { $0 }

        if panel.runModal() == .OK {
            for url in panel.urls {
                library.importLUT(from: url)
            }
        }
    }

    /// Testable/non-panel seam for importing a file selected by another UI surface.
    func importLook(from url: URL) {
        library.importLUT(from: url)
    }

    /// Re-read configured and imported Look files. This is also the explicit user action for an
    /// external editor that replaced a file in place.
    func refreshLooks() {
        library.refresh()
    }

    func chooseLUTFolder() { chooseLookFolder() }

    private func saveActiveDocument(force: Bool = false) {
        guard let activeAssetID, let activeSourceReference else { return }
        editSessions[activeAssetID] = PhotoEditSession(document: document, history: activeHistory)
        nextEditSessionRevision &+= 1
        editSessionRevisions[activeAssetID] = nextEditSessionRevision

        queuePersistence(document, for: activeSourceReference, reportsStatus: true, force: force)
    }

    /// Serialize disk snapshots in edit order. This is shared with multi-photo paste because a
    /// destination that was never opened does not pass through `saveActiveDocument` before quit.
    private func queuePersistence(
        _ document: EditDocument,
        for reference: EditSourceReference,
        reportsStatus: Bool,
        force: Bool = false
    ) {
        let assetID = reference.assetID
        let priorForce = pendingPersistence[assetID]?.force ?? false
        pendingPersistence[assetID] = PendingPersistence(
            document: document, reference: reference,
            reportsStatus: reportsStatus || (pendingPersistence[assetID]?.reportsStatus ?? false),
            force: force || priorForce
        )
        peakPendingPersistence = max(peakPendingPersistence, pendingPersistence.count)
        guard persistenceTask == nil || force else { return }
        let previous = persistenceTask
        if force { previous?.cancel() }
        startPersistenceWorker(force: force, after: previous)
    }

    /// Chain onto `previous` rather than letting a cancelled worker run orphaned: cancelling a task
    /// only stops it from starting its *next* save, it does not abort a save already in flight. If a
    /// forced restart simply replaced `persistenceTask`, `flushPendingWrites` — which only awaits the
    /// current `persistenceTask` — could return while that orphaned save was still writing to disk.
    /// Awaiting `previous` first keeps writes serialized to at most one in flight and keeps
    /// `flushPendingWrites` a real guarantee.
    private func startPersistenceWorker(force: Bool, after previous: Task<Void, Never>?) {
        persistenceGeneration &+= 1
        let generation = persistenceGeneration
        persistenceTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            if !force { try? await Task.sleep(for: Self.persistenceCheckpoint) }
            await self.drainPersistence(generation: generation)
        }
    }

    private func drainPersistence(generation: Int) async {
        while !Task.isCancelled, let assetID = pendingPersistence.keys.sorted(by: { $0.description < $1.description }).first,
              let snapshot = pendingPersistence[assetID] {
            do {
                try await editStore.save(snapshot.document, for: snapshot.reference)
                if pendingPersistence[assetID] == snapshot { pendingPersistence.removeValue(forKey: assetID) }
                if snapshot.reportsStatus { editStoreStatus = nil }
            } catch {
                // Keep the snapshot dirty. A later edit or termination flush retries it rather than
                // falsely presenting a durable state that never reached disk.
                editStoreStatus = error.localizedDescription
                statusMessage = error.localizedDescription
                break
            }
            if !snapshot.force, !pendingPersistence.isEmpty {
                try? await Task.sleep(for: Self.persistenceCheckpoint)
            }
        }
        if persistenceGeneration == generation { persistenceTask = nil }
    }

    private func requestPersistenceFlush() {
        guard !pendingPersistence.isEmpty else { return }
        let previous = persistenceTask
        previous?.cancel()
        startPersistenceWorker(force: true, after: previous)
    }

    /// Wait for queued snapshots before clean application termination.
    public func flushPendingWrites() async {
        requestPersistenceFlush()
        while let pending = persistenceTask { await pending.value }
    }
}
