import SwiftUI

/// The empty browser has a small, explicit presentation matrix so its copy and icon stay aligned
/// across the initial, loading, unavailable-folder, and missing-reference states. Keeping this
/// decision outside the `ViewBuilder` also makes the view-level state matrix easy to exercise.
enum LookInspectorEmptyState: Equatable, Sendable {
    case scanning
    case folderUnavailable
    case missingReference
    case emptyFolder
    case firstLook
    case populated

    static func resolve(
        isScanning: Bool,
        lookCount: Int,
        folderConfigured: Bool,
        scanError: String?,
        hasMissingReference: Bool = false
    ) -> Self {
        if lookCount > 0 { return .populated }
        if isScanning { return .scanning }
        if scanError != nil { return .folderUnavailable }
        if hasMissingReference { return .missingReference }
        return folderConfigured ? .emptyFolder : .firstLook
    }

    var title: String {
        switch self {
        case .scanning: return "Scanning for Looks…"
        case .folderUnavailable: return "Look folder unavailable"
        case .missingReference: return "Look unavailable"
        case .emptyFolder: return "No Looks found"
        case .firstLook: return "Bring in your first Look"
        case .populated: return "Looks"
        }
    }

    var message: String {
        switch self {
        case .scanning:
            return "Lumo is checking the selected folder for external .cube and .look files."
        case .folderUnavailable:
            return "Choose another Look folder, or import a file from anywhere."
        case .missingReference:
            return "This photo references a Look that is no longer available. Clear the reference or import the file again."
        case .emptyFolder:
            return "Add .cube or .look files to the selected folder, or import one from anywhere."
        case .firstLook:
            return "Try a bundled starter library Look, import an external .cube or .look file, or choose a folder to browse your own Looks."
        case .populated:
            return "Browse and apply a Look."
        }
    }

    var iconName: String {
        switch self {
        case .scanning: return "arrow.triangle.2.circlepath"
        case .folderUnavailable, .missingReference: return "exclamationmark.triangle"
        case .emptyFolder: return "folder"
        case .firstLook, .populated: return "wand.and.stars"
        }
    }
}

/// The one optional Look stage: a searchable, folder-aware browser for `.cube` looks and their
/// per-photo intensity. It is hosted in the editor inspector so Look is available without making
/// one a prerequisite for ordinary editing.
struct LookInspectorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchText = ""

    /// Names of collapsed folders. Stored as a set of category names (a folder absent from the set
    /// is expanded), so newly-discovered folders default to expanded. Persisted across launches and
    /// re-scans.
    private static let collapsedKey = "lumo.collapsedLUTCategories"
    @State private var collapsed: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: LookInspectorView.collapsedKey) ?? [])

    private var isSearching: Bool { !searchText.isEmpty }
    private var hasLooks: Bool { !viewModel.library.allLUTs.isEmpty }

    private var filteredCategories: [LUTLibrary.Category] {
        if searchText.isEmpty {
            return viewModel.library.categories
        }
        let query = searchText.lowercased()
        return viewModel.library.categories.compactMap { category in
            // A folder-name match surfaces the whole folder; otherwise keep only the looks whose
            // own name matches.
            if category.name.lowercased().contains(query) {
                return category
            }
            let filtered = category.luts.filter { $0.name.lowercased().contains(query) }
            return filtered.isEmpty
                ? nil
                : LUTLibrary.Category(id: category.id, name: category.name, luts: filtered, source: category.source)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if hasLooks {
                searchField
                if let scanError = viewModel.library.scanError {
                    folderErrorBanner(scanError)
                }
                if let importError = viewModel.library.importError {
                    importErrorBanner(importError)
                }
                Divider()
                lookList
                if !viewModel.library.bundledAcknowledgement.isEmpty,
                   viewModel.library.allLUTs.contains(where: { $0.source == .bundled }) {
                    starterAcknowledgement
                }
                unresolvedLookSection
                intensitySection
            } else {
                emptyState
            }
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
        .background(LumoTheme.windowBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Look adjustments")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Look")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if filteredCategories.count > 1 {
                Button(action: toggleAll) {
                    Image(systemName: allExpanded ? "rectangle.compress.vertical"
                                                   : "rectangle.expand.vertical")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(isSearching)
                .help(allExpanded ? "Collapse all folders" : "Expand all folders")
            }

            if hasLooks {
                Button {
                    viewModel.chooseLookFile()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Import a Look file")
                .accessibilityLabel("Import Look")
            }

            Button {
                viewModel.refreshLooks()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Refresh Look files")

            Button {
                viewModel.presentRecipeExtractor()
            } label: {
                Image(systemName: "wand.and.stars")
            }
            .buttonStyle(.borderless)
            .help("Derive a look from a RAW and JPG")

            Button {
                viewModel.chooseLookFolder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Choose Look folder")

            Button("Reset") {
                viewModel.resetLook()
            }
            .buttonStyle(.link)
            .disabled(!viewModel.hasLookAdjustments)
            .help("Reset the Look stage")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search looks", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(LumoTheme.controlBackground, in: RoundedRectangle(cornerRadius: 6))
        .onExitCommand { searchText = "" }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        let state = LookInspectorEmptyState.resolve(
            isScanning: viewModel.library.isScanning,
            lookCount: viewModel.library.allLUTs.count,
            folderConfigured: viewModel.library.folderURL != nil,
            scanError: viewModel.library.scanError,
            hasMissingReference: viewModel.selectedLookID != nil && viewModel.selectedLook == nil
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    if state == .scanning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                            .accessibilityLabel("Scanning Look folder")
                    } else {
                        Image(systemName: state.iconName)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                            .accessibilityHidden(true)
                    }

                    Text(state.title)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(state.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let scanError = viewModel.library.scanError {
                    folderErrorBanner(scanError)
                }

                if let importError = viewModel.library.importError {
                    importErrorBanner(importError)
                }

                if viewModel.selectedLookID != nil && viewModel.selectedLook == nil {
                    unresolvedLookSection
                }

                importLookButton

                Button {
                    viewModel.chooseLookFolder()
                } label: {
                    Label("Choose Look Folder…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Choose a folder containing Look files")
                .accessibilityHint("Browse for a folder containing external cube or look files")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Look inspector: \(state.title)")
    }

    private var importLookButton: some View {
        Button {
            viewModel.chooseLookFile()
        } label: {
            Label(
                viewModel.library.isImporting ? "Importing Look…" : "Import Look",
                systemImage: viewModel.library.isImporting ? "hourglass" : "plus"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.library.isImporting)
        .help(viewModel.library.isImporting ? "Importing Look…" : "Import an external .cube or .look file")
        .accessibilityLabel(viewModel.library.isImporting ? "Importing Look" : "Import Look")
        .accessibilityHint(
            viewModel.library.isImporting
                ? "Wait for the current Look import to finish"
                : "Choose an external cube or look file"
        )
    }

    private func folderErrorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityLabel("Look folder warning: \(message)")
    }

    private func importErrorBanner(_ message: String) -> some View {
        Label(message, systemImage: "xmark.octagon")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityLabel("Look import error: \(message)")
    }

    private var lookList: some View {
        List(selection: selectedLookBinding) {
            Section {
                Button {
                    viewModel.selectLook(nil)
                } label: {
                    LookNoneRow(isSelected: viewModel.isLookNoneSelected)
                }
                .buttonStyle(.plain)
                .tag(nil as LUTID?)
            } header: {
                HStack {
                    Text("Look")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.library.allLUTs.count)")
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }

            if viewModel.library.isScanning && viewModel.library.allLUTs.isEmpty {
                scanningRow
            } else if viewModel.library.allLUTs.isEmpty {
                emptyFolderRow
            } else {
                ForEach(filteredCategories) { category in
                    Section(isExpanded: isExpandedBinding(category.id)) {
                        ForEach(category.luts) { lut in
                            Button {
                                // Keep the click path ID-based. The library may replace the
                                // in-memory CubeLUT during a rescan, while the document stores
                                // only this stable identity.
                                viewModel.selectLook(id: lut.lutID)
                            } label: {
                                LookRow(
                                    look: lut,
                                    isSelected: viewModel.selectedLookID == lut.lutID
                                )
                            }
                            .buttonStyle(.plain)
                            .tag(Optional(lut.lutID))
                        }
                    } header: {
                        HStack {
                            Text(category.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if category.source == .bundled {
                                Text("Starter • Read-only")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .accessibilityLabel("Starter Looks, read-only")
                            }
                            Spacer()
                            Text("\(category.luts.count)")
                                .font(.caption2)
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var selectedLookBinding: Binding<LUTID?> {
        Binding(
            get: { viewModel.selectedLookID },
            set: { viewModel.selectLook(id: $0) }
        )
    }

    private var scanningRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Scanning Look folder…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tag(nil as LUTID?)
    }

    private var emptyFolderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.library.scanError ?? "No Look folder configured")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose Folder…") {
                viewModel.chooseLookFolder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .tag(nil as LUTID?)
    }

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Intensity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((viewModel.lookIntensity * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { viewModel.lookIntensity },
                    set: { viewModel.setLookIntensity($0) }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        viewModel.beginPreviewInteraction()
                    } else {
                        viewModel.endPreviewInteraction()
                    }
                }
            )
            .accessibilityLabel("Look intensity")
            .accessibilityValue("\(Int((viewModel.lookIntensity * 100).rounded())) percent")
            .disabled(viewModel.selectedLook == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var starterAcknowledgement: some View {
        Text(viewModel.library.bundledAcknowledgement)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityLabel("Starter Look acknowledgement: \(viewModel.library.bundledAcknowledgement)")
    }

    @ViewBuilder
    private var unresolvedLookSection: some View {
        if viewModel.selectedLookID != nil && viewModel.selectedLook == nil {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    viewModel.lutResolutionStatus ?? "This Look is still resolving.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button("Clear Look Reference") {
                    viewModel.selectLook(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Remove the unavailable Look from this photo")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.08))
        }
    }

    // MARK: - Folder collapse state

    private var allExpanded: Bool {
        collapsed.isDisjoint(with: Set(filteredCategories.map(\.id)))
    }

    private func isExpandedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { isSearching || !collapsed.contains(id) },
            set: { expand in
                guard !isSearching else { return }
                if expand { collapsed.remove(id) } else { collapsed.insert(id) }
                persistCollapsed()
            }
        )
    }

    private func toggleAll() {
        let ids = Set(filteredCategories.map(\.id))
        if allExpanded {
            collapsed.formUnion(ids)
        } else {
            collapsed.subtract(ids)
        }
        persistCollapsed()
    }

    private func persistCollapsed() {
        UserDefaults.standard.set(Array(collapsed), forKey: Self.collapsedKey)
    }
}

private struct LookNoneRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 4, height: 20)
            Image(systemName: "circle.slash")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text("None")
                .font(.system(.body, design: .default))
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.weight(.semibold))
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel("None")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct LookRow: View {
    let look: CubeLUT
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 4, height: 20)

            LookPreviewSwatch(look: look)

            Text(look.name)
                .font(.system(.body, design: .default))
                .lineLimit(1)

            Spacer()
            Text(look.source.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .accessibilityHidden(true)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.weight(.semibold))
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(look.name), \(look.source.accessibilityDescription)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct LookPreviewSwatch: View {
    let look: CubeLUT

    private var colors: [Color] {
        let values = look.tableFloats
        let count = max(1, values.count / 4)
        let indices = [0, count / 4, count / 2, max(0, count - 1)]
        return indices.map { index in
            let offset = min(index, count - 1) * 4
            return Color(
                red: Double(values[offset]),
                green: Double(values[offset + 1]),
                blue: Double(values[offset + 2])
            )
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .frame(width: 42, height: 20)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.18), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
