import Foundation

/// Bounded undo/redo state for one photo.
///
/// History stores only value-state documents. Rendered images and Core Image objects never enter
/// the history, so a long editing session has a predictable memory cost.
struct EditHistory: Sendable, Equatable {
    static let maximumDepth = 100

    private(set) var undoSnapshots: [EditDocument] = []
    private(set) var redoSnapshots: [EditDocument] = []
    private var groupingStart: EditDocument?

    var canUndo: Bool { !undoSnapshots.isEmpty }
    var canRedo: Bool { !redoSnapshots.isEmpty }
    var isGrouping: Bool { groupingStart != nil }
    var undoCount: Int { undoSnapshots.count }
    var redoCount: Int { redoSnapshots.count }

    mutating func beginGrouping(document: EditDocument) {
        if groupingStart == nil { groupingStart = document }
    }

    mutating func endGrouping(document: EditDocument) {
        guard let start = groupingStart else { return }
        groupingStart = nil
        guard start != document else { return }
        appendUndo(start)
    }

    mutating func recordChange(from old: EditDocument, to new: EditDocument) {
        guard old != new else { return }
        redoSnapshots.removeAll(keepingCapacity: true)
        guard groupingStart == nil else { return }
        appendUndo(old)
    }

    mutating func undo(current: EditDocument) -> EditDocument? {
        guard let previous = undoSnapshots.popLast() else { return nil }
        appendRedo(current)
        return previous
    }

    mutating func redo(current: EditDocument) -> EditDocument? {
        guard let next = redoSnapshots.popLast() else { return nil }
        appendUndo(current)
        return next
    }

    private mutating func appendUndo(_ document: EditDocument) {
        undoSnapshots.append(document)
        trim(&undoSnapshots)
    }

    private mutating func appendRedo(_ document: EditDocument) {
        redoSnapshots.append(document)
        trim(&redoSnapshots)
    }

    private func trim(_ snapshots: inout [EditDocument]) {
        let excess = snapshots.count - Self.maximumDepth
        if excess > 0 { snapshots.removeFirst(excess) }
    }
}

/// The unsaved edit state retained for one photo while the app is open.
struct PhotoEditSession: Sendable, Equatable {
    var document = EditDocument()
    var history = EditHistory()
}
