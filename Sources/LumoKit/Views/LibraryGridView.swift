import AppKit
import SwiftUI

/// The grid-first browsing surface for a source collection.
///
/// `LazyVGrid` is important here: the collection may contain thousands of `PhotoAsset` values, but
/// SwiftUI only hosts the cells around the viewport. Each hosted cell opts into thumbnail work from
/// `onAppear`, and releases in-flight work from `onDisappear`, so scrolling does not create a decode
/// task for the entire folder.
struct LibraryGridView: View {
    @ObservedObject var collection: ImageCollection
    let onOpen: () -> Void

    private let layout = LibraryGridLayout()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: CGFloat(layout.minimumCellWidth)), spacing: CGFloat(layout.spacing))],
                    spacing: CGFloat(layout.spacing)
                ) {
                    ForEach(Array(collection.items.enumerated()), id: \.element.id) { index, item in
                        LibraryGridCell(
                            item: item,
                            isSelected: collection.selection.selectedIDs.contains(item.id),
                            isActive: collection.selection.activeID == item.id
                        )
                        .onAppear {
                            // Make the cell callback order-independent: SwiftUI may deliver a
                            // child's appearance before its container's appearance.
                            collection.beginThumbnailDemand()
                            collection.requestThumbnail(for: item.id)
                        }
                        .onDisappear {
                            collection.releaseThumbnail(for: item.id)
                        }
                        .onTapGesture {
                            select(index: index)
                        }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                select(index: index)
                                onOpen()
                            }
                        )
                        .accessibilityAddTraits(
                            collection.selection.selectedIDs.contains(item.id) ? .isSelected : []
                        )
                        .accessibilityHint("Double-click to edit")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
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

private struct LibraryGridCell: View {
    let item: ImageCollection.Item
    let isSelected: Bool
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
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
                .aspectRatio(contentMode: .fill)
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
