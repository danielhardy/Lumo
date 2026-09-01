import AppKit
import SwiftUI

/// The grid-first browsing surface for a source collection.
///
/// `LazyVStack` is important here: the collection may contain thousands of `PhotoAsset` values, but
/// SwiftUI only hosts the rows around the viewport. Each hosted cell opts into thumbnail work from
/// `onAppear`, and releases in-flight work from `onDisappear`, so scrolling does not create a decode
/// task for the entire folder.
struct LibraryGridView: View {
    @ObservedObject var collection: ImageCollection
    let onOpen: () -> Void

    private let layout = LibraryGridLayout()
    @State private var mosaicCache = LibraryMosaicLayoutCache()

    var body: some View {
        VStack(spacing: 0) {
            LibraryFilterBar(collection: collection)
            Divider()

            GeometryReader { geometry in
                if collection.filteredIndices.isEmpty {
                    LibraryEmptyState(collection: collection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        let indices = collection.filteredIndices
                        let itemIDs = indices.map { collection.items[$0].id }
                        let rows = mosaicCache.rows(
                            itemIDs: itemIDs,
                            width: max(1, geometry.size.width - 32),
                            layout: layout,
                            aspectRatioAt: { offset in
                                collection.items[indices[offset]].libraryAspectRatio
                            }
                        )
                        LazyVStack(alignment: .leading, spacing: CGFloat(layout.spacing)) {
                            ForEach(rows) { row in
                                LibraryMosaicRow(
                                    row: row,
                                    sourceIndices: indices,
                                    collection: collection,
                                    spacing: layout.spacing,
                                    onSelect: select(index:),
                                    onOpen: onOpen
                                )
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                    }
                    .background(LumoTheme.windowBackground)
                }
            }
        }
        .background(LumoTheme.windowBackground)
        .onAppear {
            collection.beginThumbnailDemand()
        }
        .overlay(alignment: .bottomLeading) {
            if collection.isScanning {
                Label("Scanning…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
        }
    }

    private func select(index: Int) {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: LibrarySelectionModel.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        collection.select(at: index, modifiers: modifiers)
    }
}

private struct LibraryMosaicRow: View {
    let row: LibraryGridLayout.MosaicRow
    let sourceIndices: [Int]
    @ObservedObject var collection: ImageCollection
    let spacing: Double
    let onSelect: (Int) -> Void
    let onOpen: () -> Void

    private var cells: [LibraryMosaicCellLayout] {
        zip(row.itemIndices, row.itemWidths).map { offset, width in
            LibraryMosaicCellLayout(
                offset: offset,
                width: width,
                id: collection.items[sourceIndices[offset]].id
            )
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: CGFloat(spacing)) {
            ForEach(cells) { cell in
                let index = sourceIndices[cell.offset]
                let item = collection.items[index]
                LibraryGridCell(
                    item: item,
                    isSelected: collection.selection.selectedIDs.contains(item.id),
                    isActive: collection.selection.activeID == item.id,
                    imageWidth: cell.width,
                    imageHeight: row.imageHeight
                )
                .frame(width: CGFloat(cell.width))
                .onAppear {
                    // Make the cell callback order-independent: SwiftUI may deliver a child's
                    // appearance before its row's appearance.
                    collection.beginThumbnailDemand()
                    collection.requestThumbnail(for: item.id)
                }
                .onDisappear {
                    collection.releaseThumbnail(for: item.id)
                }
                .onTapGesture {
                    onSelect(index)
                }
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        onSelect(index)
                        onOpen()
                    }
                )
                .accessibilityAddTraits(
                    collection.selection.selectedIDs.contains(item.id) ? .isSelected : []
                )
                .accessibilityHint("Double-click to edit")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LibraryMosaicCellLayout: Identifiable {
    let offset: Int
    let width: Double
    let id: PhotoAssetID
}

private struct LibraryFilterBar: View {
    @ObservedObject var collection: ImageCollection

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            Picker("Flag", selection: flagBinding) {
                ForEach(LibraryFlagFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Picker("Rating", selection: ratingBinding) {
                Text("Any rating").tag(LibraryRatingFilter.any)
                ForEach(1...5, id: \.self) { rating in
                    Text("\(rating)+ stars").tag(LibraryRatingFilter.minimum(rating))
                }
                Divider()
                ForEach(0...5, id: \.self) { rating in
                    Text("Exactly \(rating) stars").tag(LibraryRatingFilter.exact(rating))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Text("\(collection.filteredItemCount) of \(collection.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if collection.filter.isFiltered {
                Button("Clear filters") { collection.clearFilter() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library filters")
    }

    private var flagBinding: Binding<LibraryFlagFilter> {
        Binding(
            get: { collection.filter.flag },
            set: { value in
                var filter = collection.filter
                filter.flag = value
                collection.setFilter(filter)
            }
        )
    }

    private var ratingBinding: Binding<LibraryRatingFilter> {
        Binding(
            get: { collection.filter.rating },
            set: { value in
                var filter = collection.filter
                filter.rating = value
                collection.setFilter(filter)
            }
        )
    }
}

private struct LibraryEmptyState: View {
    @ObservedObject var collection: ImageCollection

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: collection.items.isEmpty ? "photo.on.rectangle.angled" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(collection.items.isEmpty ? "No photos in this library" : "No photos match these filters")
                .font(.headline)
            if collection.filter.isFiltered {
                Button("Clear filters") { collection.clearFilter() }
                    .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryGridCell: View {
    let item: ImageCollection.Item
    let isSelected: Bool
    let isActive: Bool
    let imageWidth: Double
    let imageHeight: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
                .frame(width: CGFloat(imageWidth), height: CGFloat(imageHeight))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isActive ? Color.accentColor : (isSelected ? Color.accentColor.opacity(0.7) : .clear),
                        lineWidth: isActive ? 3 : 2
                    )
            }

            HStack(spacing: 5) {
                Text(item.displayName)
                    .font(.caption)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                stateBadges
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnail = item.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if item.asset.thumbnailState == .failed {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    if item.asset.thumbnailState == .loading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                }
        }
    }

    private var stateBadges: some View {
        HStack(spacing: 5) {
            if item.asset.rating > 0 {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Rating \(item.asset.rating) of 5")
            }
            switch item.asset.flag {
            case .pick:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .reject:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .none:
                EmptyView()
            }
        }
        .font(.caption2.weight(.semibold))
        .frame(minWidth: 14)
    }
}
