import Foundation

/// The modifier-aware selection state used by the library grid.
///
/// `activeID` is the one photo that owns the edit handoff. It is deliberately separate from
/// `selectedIDs`, which may contain a batch for later culling or editing operations. `anchorID`
/// is the stable end of a range selection, matching the way native macOS lists extend a selection
/// from the last ordinary click.
struct LibrarySelectionModel: Equatable, Sendable {
    struct Modifiers: OptionSet, Sendable, Hashable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
    }

    private(set) var selectedIDs: Set<PhotoAssetID> = []
    private(set) var activeID: PhotoAssetID?
    private(set) var anchorID: PhotoAssetID?
    private var selectionOrder: [PhotoAssetID] = []

    init() {}

    var isEmpty: Bool { selectedIDs.isEmpty }

    /// Apply one click using native macOS list semantics:
    ///
    /// - ordinary click replaces the selection and establishes a new range anchor;
    /// - Command-click toggles one item and makes it active;
    /// - Shift-click extends from the anchor, preserving an existing discontiguous selection.
    mutating func click(
        _ id: PhotoAssetID,
        in orderedIDs: [PhotoAssetID],
        modifiers: Modifiers = []
    ) {
        guard orderedIDs.contains(id) else { return }

        if modifiers.contains(.shift) {
            let rangeAnchor = anchorID.flatMap { orderedIDs.contains($0) ? $0 : nil }
                ?? activeID.flatMap { orderedIDs.contains($0) ? $0 : nil }
                ?? id
            let range = contiguousRange(from: rangeAnchor, to: id, in: orderedIDs)
            selectedIDs.formUnion(range)
            selectionOrder = orderedIDs.filter { selectedIDs.contains($0) }
            activeID = id
            anchorID = rangeAnchor
            return
        }

        if modifiers.contains(.command) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
                selectionOrder.removeAll { $0 == id }
                activeID = selectionOrder.last
                anchorID = activeID
            } else {
                selectedIDs.insert(id)
                selectionOrder.append(id)
                activeID = id
                anchorID = id
            }
            return
        }

        selectedIDs = [id]
        selectionOrder = [id]
        activeID = id
        anchorID = id
    }

    mutating func selectAll(in orderedIDs: [PhotoAssetID]) {
        selectedIDs = Set(orderedIDs)
        selectionOrder = orderedIDs
        if let activeID, selectedIDs.contains(activeID) {
            anchorID = anchorID.flatMap { selectedIDs.contains($0) ? $0 : nil } ?? activeID
        } else {
            activeID = orderedIDs.first
            anchorID = activeID
        }
    }

    /// Make an item the keyboard focus while retaining any multi-selection that is still useful.
    /// This is used when a filter hides the previous active item; hidden selected IDs remain in the
    /// model and are not confused with culling state.
    mutating func focus(_ id: PhotoAssetID, in orderedIDs: [PhotoAssetID]) {
        guard orderedIDs.contains(id) else { return }
        if !selectedIDs.contains(id) {
            selectedIDs.insert(id)
            selectionOrder.append(id)
        }
        activeID = id
        anchorID = id
    }

    mutating func clear() {
        selectedIDs.removeAll()
        selectionOrder.removeAll()
        activeID = nil
        anchorID = nil
    }

    /// Drop IDs removed by a rescan without allowing a stale selection or edit target to survive.
    mutating func reconcile(with orderedIDs: [PhotoAssetID]) {
        let available = Set(orderedIDs)
        selectedIDs = selectedIDs.intersection(available)
        selectionOrder = selectionOrder.filter { selectedIDs.contains($0) }

        if let activeID, selectedIDs.contains(activeID) {
            self.activeID = activeID
        } else {
            self.activeID = selectionOrder.last ?? orderedIDs.first(where: { selectedIDs.contains($0) })
        }
        if let anchorID, selectedIDs.contains(anchorID) {
            self.anchorID = anchorID
        } else {
            self.anchorID = self.activeID
        }
    }

    func orderedIDs(from orderedIDs: [PhotoAssetID]) -> [PhotoAssetID] {
        orderedIDs.filter { selectedIDs.contains($0) }
    }

    private func contiguousRange(
        from start: PhotoAssetID,
        to end: PhotoAssetID,
        in orderedIDs: [PhotoAssetID]
    ) -> [PhotoAssetID] {
        guard let startIndex = orderedIDs.firstIndex(of: start),
              let endIndex = orderedIDs.firstIndex(of: end) else { return [end] }
        let bounds = min(startIndex, endIndex)...max(startIndex, endIndex)
        return Array(orderedIDs[bounds])
    }
}

/// Geometry shared by the library mosaic and its performance test. The view uses a `LazyVStack`
/// of justified rows for virtualization; this value type keeps the row grouping deterministic and
/// makes a synthetic 1,000-item profile independent of SwiftUI's view-hosting machinery.
struct LibraryGridLayout: Sendable, Equatable {
    struct MosaicRow: Sendable, Equatable, Identifiable {
        let id: Int
        let itemIndices: [Int]
        let imageHeight: Double
        let itemWidths: [Double]
    }

    let minimumCellWidth: Double
    let cellHeight: Double
    let spacing: Double
    let prefetchRows: Int

    init(
        minimumCellWidth: Double = 156,
        cellHeight: Double = 174,
        spacing: Double = 12,
        prefetchRows: Int = 2
    ) {
        self.minimumCellWidth = max(1, minimumCellWidth)
        self.cellHeight = max(1, cellHeight)
        self.spacing = max(0, spacing)
        self.prefetchRows = max(0, prefetchRows)
    }

    func columnCount(for width: Double) -> Int {
        max(1, Int((max(0, width) + spacing) / (minimumCellWidth + spacing)))
    }

    /// Build a justified photo mosaic. Items are grouped in source order, with each row sharing
    /// one image height and each cell's width derived from its source aspect ratio. A candidate
    /// row is closed before it becomes too dense or would make a cell uncomfortably narrow. The
    /// final row is intentionally left-aligned; forcing it to fill the viewport would make a
    /// short tail row unexpectedly tall and would cause a visible scroll jump while scanning.
    ///
    /// The returned geometry is pure value data. It can therefore be tested without constructing
    /// SwiftUI views, and the same result is used for every cell in a row so no overlap can be
    /// introduced by independent child measurements.
    func mosaicRows(aspectRatios: [Double], width: Double) -> [MosaicRow] {
        guard !aspectRatios.isEmpty, width > 0 else { return [] }

        let contentWidth = max(width, minimumCellWidth)
        let targetHeight = cellHeight
        let minimumMosaicWidth = max(96, minimumCellWidth * 0.72)
        let usableRatios = aspectRatios.map { Self.normalizedAspectRatio($0) }
        var rows: [MosaicRow] = []
        var currentIndices: [Int] = []
        var currentRatios: [Double] = []

        func candidateHeight(for ratios: [Double]) -> Double {
            guard !ratios.isEmpty else { return 0 }
            let gaps = spacing * Double(max(0, ratios.count - 1))
            return max(1, (contentWidth - gaps) / ratios.reduce(0, +))
        }

        func canFit(_ ratios: [Double]) -> Bool {
            let height = candidateHeight(for: ratios)
            return ratios.allSatisfy { $0 * height >= minimumMosaicWidth }
        }

        func appendRow(isLast: Bool) {
            guard !currentIndices.isEmpty else { return }
            let idealHeight = candidateHeight(for: currentRatios)
            // Keep single-item and tail rows from becoming enormous. Full rows are allowed to be
            // a little taller than the target when that is what preserves useful cell widths.
            let upperBound = targetHeight * 1.45
            let height = isLast
                ? min(targetHeight, idealHeight)
                : min(upperBound, idealHeight)
            let widths = currentRatios.map { $0 * height }
            rows.append(MosaicRow(
                id: currentIndices[0],
                itemIndices: currentIndices,
                imageHeight: height,
                itemWidths: widths
            ))
            currentIndices.removeAll(keepingCapacity: true)
            currentRatios.removeAll(keepingCapacity: true)
        }

        for (index, ratio) in usableRatios.enumerated() {
            let candidate = currentRatios + [ratio]
            let shouldClose = !currentRatios.isEmpty && (
                !canFit(candidate)
                || (candidate.count > 1 && candidateHeight(for: candidate) < targetHeight)
            )
            if shouldClose {
                appendRow(isLast: false)
            }
            currentIndices.append(index)
            currentRatios.append(ratio)
        }
        appendRow(isLast: true)
        return rows
    }

    /// Normalize malformed or extreme source geometry to a useful bounded display ratio. The
    /// source dimensions remain untouched; this only protects row math from corrupt metadata.
    static func normalizedAspectRatio(_ ratio: Double) -> Double {
        guard ratio.isFinite, ratio > 0 else { return 4.0 / 3.0 }
        return min(max(ratio, 0.35), 3.0)
    }

    func visibleIndices(
        itemCount: Int,
        width: Double,
        viewportHeight: Double,
        scrollOffset: Double
    ) -> Range<Int> {
        guard itemCount > 0 else { return 0..<0 }
        let columns = columnCount(for: width)
        let rowHeight = cellHeight + spacing
        let firstRow = max(0, Int(max(0, scrollOffset) / rowHeight) - prefetchRows)
        let visibleRows = max(1, Int(ceil(max(0, viewportHeight) / rowHeight))) + prefetchRows * 2
        let start = min(itemCount, firstRow * columns)
        let end = min(itemCount, (firstRow + visibleRows) * columns)
        return start..<max(start, end)
    }
}
