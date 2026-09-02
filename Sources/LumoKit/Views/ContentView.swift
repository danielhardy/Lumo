import SwiftUI
import PhotosUI
import AppKit

/// Main window layout: sidebar + preview + toolbar.
///
/// One of two entry points LumoKit exposes to the executable (the other is
/// `LumoCommands`); everything else in the module stays internal.
public struct ContentView: View {
    @StateObject private var viewModel: AppViewModel
    @ObservedObject private var inspectorState: AppViewModel.InspectorState
    @State private var photosSelection: [PhotosPickerItem] = []
    @State private var photosImportTask: Task<Void, Never>?

    public init() {
        let viewModel = AppViewModel()
        _viewModel = StateObject(wrappedValue: viewModel)
        _inspectorState = ObservedObject(wrappedValue: viewModel.inspectorState)
    }

    /// Allows the application delegate to share the model that owns the persistence queue, so clean
    /// termination can flush the same edit catalog the window has been using.
    public init(viewModel: AppViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _inspectorState = ObservedObject(wrappedValue: viewModel.inspectorState)
    }

    public var body: some View {
        mainContent
            .navigationTitle("")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarContent
                }
            }
            .photosPicker(
                isPresented: $viewModel.isPhotosPickerPresented,
                selection: $photosSelection,
                maxSelectionCount: 50,
                matching: .images
            )
            .onChange(of: photosSelection) { _, newSelection in
                handlePhotosSelection(newSelection)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.derive.isSheetPresented },
                set: { viewModel.derive.isSheetPresented = $0 }
            )) {
                RecipeExtractorSheet(coordinator: viewModel.derive)
            }
            .modifier(KeyboardShortcuts(viewModel: viewModel))
            .modifier(MenuCommandReceivers(viewModel: viewModel))
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                ),
                presenting: viewModel.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { message in
                Text(message)
            }
    }

    private func handlePhotosSelection(_ selection: [PhotosPickerItem]) {
        guard !selection.isEmpty else { return }
        photosImportTask?.cancel()
        viewModel.beginPhotosImport(totalCount: selection.count)

        // Keep only the current transfer in this task. `ImageCollection` owns each successful
        // original after append, while the picker/provider remains cancellable between items.
        photosImportTask = Task { @MainActor in
            var wasCancelled = false
            for (ordinal, item) in selection.enumerated() {
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }

                let name = "Photo \(ordinal + 1)"
                viewModel.updatePhotosImportPhase(.transferring, name: name)
                var transferInterval = LumoSignpostInterval(
                    .photoTransfer,
                    context: LumoTraceContext(
                        sourceFingerprint: item.itemIdentifier ?? "ordinal:\(ordinal)",
                        quality: "photosImport"
                    )
                )
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        transferInterval.end()
                        viewModel.recordPhotosImportFailure(name: name)
                        continue
                    }
                    transferInterval.end()
                    guard !Task.isCancelled else {
                        wasCancelled = true
                        break
                    }
                    let payload = ImageCollection.PhotoImportItem(
                        name: name, data: data, localIdentifier: item.itemIdentifier
                    )
                    viewModel.appendPhotosImport(payload, ordinal: ordinal)
                } catch is CancellationError {
                    transferInterval.end()
                    wasCancelled = true
                    break
                } catch {
                    transferInterval.end()
                    // A provider failure is local to this item. Continue so already imported
                    // originals remain usable and later selections still get a chance to arrive.
                    viewModel.recordPhotosImportFailure(name: name)
                }
            }
            wasCancelled = wasCancelled || Task.isCancelled
            viewModel.finishPhotosImport(cancelled: wasCancelled)
            photosSelection = []
        }
    }

    private func cancelPhotosImport() {
        photosImportTask?.cancel()
    }

    private var mainContent: some View {
        NavigationStack {
            detailContent
        }
        .background(LumoTheme.windowBackground)
        .inspector(isPresented: $inspectorState.isPresented) {
            InfoInspectorView(viewModel: viewModel, inspectorState: inspectorState)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
    }

    private var detailContent: some View {
        Group {
            if viewModel.navigation.isGrid && viewModel.collection.isActive {
                VStack(spacing: 0) {
                    LibraryGridView(
                        collection: viewModel.collection,
                        onOpen: viewModel.openActiveCollectionImage
                    )
                    StatusBar(viewModel: viewModel, onCancelImport: cancelPhotosImport)
                }
            } else {
                HStack(spacing: 0) {
                    if viewModel.isSourceBrowserPresented && !viewModel.collection.items.isEmpty {
                        SourceBrowserView(viewModel: viewModel)
                            .frame(width: 240)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Divider()
                    }

                    VStack(spacing: 0) {
                        PreviewView(viewModel: viewModel)

                        if viewModel.collection.isActive {
                            Divider()
                            FilmstripView(collection: viewModel.collection) { index, additive in
                                viewModel.selectCollectionImage(at: index, additive: additive)
                            }
                            .frame(height: 100)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                            StatusBar(viewModel: viewModel, onCancelImport: cancelPhotosImport)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.collection.isActive)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSourceBrowserPresented)
        .animation(.easeInOut(duration: 0.2), value: viewModel.navigation.mode)
    }

    @ViewBuilder
    private var toolbarContent: some View {
        Picker("Workspace", selection: Binding(
            get: { viewModel.navigation.mode },
            set: { viewModel.navigate(to: $0) }
        )) {
            ForEach(NavigationState.Mode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 142)
        .help("Library (G) or Edit (E)")

        CanvasToolbarControls(
            viewModel: viewModel,
            canvasState: viewModel.canvasState,
            hasImage: viewModel.sourceImage != nil
        )

        // Side-by-side is only meaningful when the LUMO-047 comparison gate has something to show.
        // Removing the control in the unsupported state keeps every visible view affordance
        // actionable and keeps its label aligned with the rendered mode.
        if viewModel.isComparisonAvailable {
            Button {
                viewModel.toggleSideBySide()
            } label: {
                Label(
                    viewModel.isSideBySide ? "Single View" : "Side by Side",
                    systemImage: viewModel.isSideBySide ? "rectangle" : "rectangle.split.2x1"
                )
            }
            .accessibilityLabel("Comparison view")
            .accessibilityValue(viewModel.isSideBySide ? "Side by side" : "Single photo")
            .accessibilityHint("Switch comparison view (V)")
            .help("Switch between single-photo and side-by-side comparison (V)")
        }

        // Source folder browser
        Button {
            viewModel.toggleSourceBrowser()
        } label: {
            Label("Source", systemImage: "sidebar.leading")
        }
        .help("Show the source folder file browser")
        .disabled(viewModel.collection.items.isEmpty)

        // Info inspector (histogram + EXIF)
        Button {
            viewModel.toggleInspector()
        } label: {
            Label("Info", systemImage: "sidebar.right")
        }
        .help("Show histogram & EXIF (⌘I)")
        .keyboardShortcut("i", modifiers: .command)
        .disabled(viewModel.sourceImage == nil)

        // Keep reset scopes together and visible: the panel reset affects only the current stage,
        // while Reset Photo clears every edit on the active source. The File menu retains the
        // keyboard shortcut for the latter.
        Menu {
            Button("Reset " + inspectorState.tab.title) {
                viewModel.resetInspectorSection()
            }
            .disabled(inspectorState.tab == .info)

            Divider()

            Button("Reset Photo") {
                viewModel.resetPhoto()
            }
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
        .help("Reset the current adjustment section or the whole photo")
        .disabled(viewModel.sourceImage == nil)

        // Import menu
        Menu {
            Button("Open Image...") {
                viewModel.openImageDialog()
            }
            Divider()
            Button("Import from Photos...") {
                viewModel.importFromPhotos()
            }
            Button("Open Source Folder...") {
                viewModel.chooseSourceFolder()
            }
            if !viewModel.collection.items.isEmpty {
                Button("Refresh Source Folder") {
                    viewModel.refreshSource()
                }
            }
            if viewModel.photosImportProgress != nil {
                Divider()
                Button("Cancel Photos Import") {
                    cancelPhotosImport()
                }
            }
        } label: {
            Label("Import", systemImage: "photo.on.rectangle")
        }

        // Edit transfer
        Button {
            viewModel.copyAllEdits()
        } label: {
            Label("Copy Edits", systemImage: "doc.on.doc")
        }
        .help("Copy all edits from the active photo (⌘⌥C)")
        .disabled(viewModel.sourceImage == nil)

        Button {
            viewModel.pasteEdits()
        } label: {
            Label("Paste Edits", systemImage: "doc.on.clipboard")
        }
        .help("Paste edits to the active photo or current selection (⌘⌥V)")
        .disabled(!viewModel.canPasteEdits)

        Divider()

        // Export
        Button {
            viewModel.exportDialog()
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        // ⌘S is bound once, on the File ▸ Export menu item (LumoApp.swift).
        // Binding it here too gave the window two competing handlers.
        .help("Export the graded image (⌘S)")
        .disabled(viewModel.sourceImage == nil)

        // Batch export — only when a multi-image set is loaded
        if viewModel.collection.isActive {
            Button {
                viewModel.batchExportDialog()
            } label: {
                Label("Export All", systemImage: "square.and.arrow.up.on.square")
            }
            .help("Apply the current Look to all imported images and export to a folder (⌘⇧E)")
            .disabled(viewModel.isExporting)
        }
    }
}

/// Toolbar controls backed by the narrow canvas publisher. A zoom or crop-handle update can
/// refresh this small control group without causing `ContentView`'s broad model observation to
/// participate in the interaction.
private struct CanvasToolbarControls: View {
    let viewModel: AppViewModel
    @ObservedObject var canvasState: CanvasInteractionState
    let hasImage: Bool

    var body: some View {
        // Crop is a committed edit, but its in-progress rectangle stays transient until Apply.
        Button {
            viewModel.toggleCropTool()
        } label: {
            Label(
                canvasState.isCropToolActive ? "Cancel Crop" : "Crop",
                systemImage: canvasState.isCropToolActive ? "xmark" : "crop"
            )
        }
        .help(canvasState.isCropToolActive
              ? "Cancel the current crop"
              : "Crop the photo with a freeform or preset frame")
        .disabled(!hasImage)

        // Canvas navigation is presentation-only; these controls never touch the edit document.
        Menu {
            Button("Fit") { viewModel.fitCanvas() }
            Button("Fill") { viewModel.fillCanvas() }
            Divider()
            ForEach([0.25, 0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { zoom in
                Button("\(Int(zoom * 100))%") { viewModel.setCanvasZoom(CGFloat(zoom)) }
            }
            Divider()
            Button("Reset View") { viewModel.resetCanvas() }
        } label: {
            Label("\(canvasState.navigation.zoomPercent)%", systemImage: "magnifyingglass")
        }
        .help("Canvas zoom: fit, fill, or explicit zoom")
        .disabled(!hasImage)
    }
}

// The File menu, its notification names, and `MenuCommandReceivers` live in
// MenuCommands.swift.
