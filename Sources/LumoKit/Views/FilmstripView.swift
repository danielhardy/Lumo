import SwiftUI
import AppKit

/// Horizontal thumbnail strip for browsing imported images.
struct FilmstripView: View {
    @ObservedObject var collection: ImageCollection
    let onSelect: (Int, Bool) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(collection.filteredIndices, id: \.self) { index in
                        let item = collection.items[index]
                        Button {
                            let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                            onSelect(index, modifiers.contains(.command))
                        } label: {
                            FilmstripThumbnail(
                                item: item,
                                isSelected: collection.selection.selectedIDs.contains(item.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                            let direction: FilmstripNavigation.Direction =
                                press.key == .leftArrow ? .previous : .next
                            guard let adjacentIndex = FilmstripNavigation.adjacentIndex(
                                in: collection.filteredIndices,
                                selectedIndex: collection.selectedIndex,
                                direction: direction
                            ) else {
                                return .ignored
                            }
                            onSelect(adjacentIndex, false)
                            return .handled
                        }
                        .id(item.id)
                        .onAppear {
                            // Child appearance can precede the scroll view's callback, so opt into
                            // demand-driven work here as well as on the container.
                            collection.beginThumbnailDemand()
                            collection.requestThumbnail(
                                for: item.id, priority: .adjacentFilmstrip
                            )
                        }
                        .onDisappear {
                            collection.releaseThumbnail(for: item.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .onAppear { collection.beginThumbnailDemand() }
            .onChange(of: collection.selectedIndex) { _, newIndex in
                guard collection.items.indices.contains(newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(collection.items[newIndex].id, anchor: .center)
                }
            }
        }
    }
}

/// Computes filmstrip navigation in display order rather than underlying collection order. This
/// keeps keyboard stepping aligned with filtered thumbnails and gives the view a small, pure seam
/// for testing without synthesizing AppKit focus.
enum FilmstripNavigation {
    enum Direction {
        case previous
        case next
    }

    static func adjacentIndex(
        in filteredIndices: [Int],
        selectedIndex: Int,
        direction: Direction
    ) -> Int? {
        switch direction {
        case .previous:
            return filteredIndices.last { $0 < selectedIndex }
        case .next:
            return filteredIndices.first { $0 > selectedIndex }
        }
    }
}

struct FilmstripThumbnail: View {
    let item: ImageCollection.Item
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 72, height: 72)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )

            Text(item.displayName)
                .font(.system(size: 9))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 72)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
