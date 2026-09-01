import SwiftUI

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
                : LUTLibrary.Category(id: category.id, name: category.name, luts: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            lookList
            intensitySection
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

            Button {
                viewModel.chooseLookFile()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Import a Look file")

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
                            LookRow(
                                look: lut,
                                isSelected: viewModel.selectedLookID == lut.lutID
                            )
                            .tag(Optional(lut.lutID))
                        }
                    } header: {
                        HStack {
                            Text(category.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

            Text(look.name)
                .font(.system(.body, design: .default))
                .lineLimit(1)

            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.weight(.semibold))
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(look.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
