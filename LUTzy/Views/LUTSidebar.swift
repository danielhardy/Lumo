import SwiftUI

/// Sidebar showing the LUT library grouped by category.
struct LUTSidebar: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchText = ""

    private var filteredCategories: [LUTLibrary.Category] {
        if searchText.isEmpty {
            return viewModel.library.categories
        }
        let query = searchText.lowercased()
        return viewModel.library.categories.compactMap { cat in
            let filtered = cat.luts.filter { $0.name.lowercased().contains(query) }
            return filtered.isEmpty ? nil : LUTLibrary.Category(id: cat.id, name: cat.name, luts: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("LUTs")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.library.allLUTs.count)")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .quaternaryLabelColor), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Search
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider()

            // LUT list
            if viewModel.library.allLUTs.isEmpty {
                emptyState
            } else {
                lutList
            }
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "cube.transparent")
                .font(.system(size: 32))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Text("No LUTs loaded")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Choose Folder...") {
                viewModel.chooseLUTFolder()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var lutList: some View {
        List(selection: Binding(
            get: { viewModel.selectedLUT },
            set: { viewModel.selectLUT($0) }
        )) {
            ForEach(filteredCategories) { category in
                Section(header: Text(category.name).font(.caption).foregroundColor(.secondary)) {
                    ForEach(category.luts) { lut in
                        LUTRow(lut: lut, isSelected: viewModel.selectedLUT == lut)
                            .tag(lut)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct LUTRow: View {
    let lut: CubeLUT
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 4, height: 20)

            Text(lut.name)
                .font(.system(.body, design: .default))
                .lineLimit(1)

            Spacer()
        }
        .contentShape(Rectangle())
    }
}
