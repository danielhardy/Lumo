import SwiftUI
import PhotosUI
import AppKit

/// Main window layout: sidebar + preview + toolbar.
///
/// One of two entry points LumoKit exposes to the executable (the other is
/// `LumoCommands`); everything else in the module stays internal.
public struct ContentView: View {
    @StateObject private var viewModel: AppViewModel
    @State private var photosSelection: [PhotosPickerItem] = []

    public init() {
        _viewModel = StateObject(wrappedValue: AppViewModel())
    }

    /// Allows the application delegate to share the model that owns the persistence queue, so clean
    /// termination can flush the same edit catalog the window has been using.
    public init(viewModel: AppViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
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
        Task {
            var dataItems: [(name: String, data: Data)] = []
            for (i, item) in selection.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    dataItems.append((name: "Photo \(i + 1)", data: data))
                }
            }
            photosSelection = []
            if !dataItems.isEmpty {
                viewModel.importPhotosData(dataItems)
            }
        }
    }

    private var mainContent: some View {
        NavigationStack {
            detailContent
        }
        .inspector(isPresented: $viewModel.isInspectorPresented) {
            InfoInspectorView(viewModel: viewModel)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
    }

    private var detailContent: some View {
        Group {
            if viewModel.isLibraryGridPresented && viewModel.collection.isActive {
                VStack(spacing: 0) {
                    LibraryGridView(
                        collection: viewModel.collection,
                        onOpen: viewModel.openActiveCollectionImage
                    )
                    StatusBar(viewModel: viewModel)
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

                        StatusBar(viewModel: viewModel)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.collection.isActive)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSourceBrowserPresented)
    }

    @ViewBuilder
    private var toolbarContent: some View {
        // Format picker
        Picker("Format", selection: $viewModel.exportFormat) {
            ForEach(ExportFormat.allCases) { fmt in
                Text(fmt.rawValue).tag(fmt)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)

        Divider()

        // Side-by-side toggle
        Button {
            viewModel.toggleSideBySide()
        } label: {
            Label(
                viewModel.isSideBySide ? "Single View" : "Side by Side",
                systemImage: viewModel.isSideBySide ? "rectangle" : "rectangle.split.2x1"
            )
        }
        .help("Toggle side-by-side comparison (V)")

        // Source folder browser
        Button {
            viewModel.toggleLibraryGrid()
        } label: {
            Label("Library", systemImage: "square.grid.2x2")
        }
        .help("Show the virtualized photo library grid")
        .disabled(viewModel.collection.items.isEmpty)

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

        Divider()

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
        } label: {
            Label("Import", systemImage: "photo.on.rectangle")
        }

        // Edit transfer
        Button {
            viewModel.copyAllEdits()
        } label: {
            Label("Copy Edits", systemImage: "doc.on.doc")
        }
        .help("Copy all edits from the active photo (⌘C)")
        .disabled(viewModel.sourceImage == nil)

        Button {
            viewModel.pasteEdits()
        } label: {
            Label("Paste Edits", systemImage: "doc.on.clipboard")
        }
        .help("Paste edits to the active photo or current selection (⌘V)")
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
            .help("Apply the current LUT to all imported images and export to a folder (⌘⇧E)")
            .disabled(viewModel.isExporting)
        }
    }
}

// The File menu, its notification names, and `MenuCommandReceivers` live in
// MenuCommands.swift.
