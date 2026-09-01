import Foundation

/// The visible workspace of the application.
///
/// Navigation is intentionally a small value type rather than a collection of view flags. The
/// library owns photo selection, the view model owns the active edit document, and this value only
/// answers which workspace should be composed around them.
struct NavigationState: Equatable, Sendable {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case grid
        case edit

        var id: Self { self }

        var title: String {
            switch self {
            case .grid: return "Library"
            case .edit: return "Edit"
            }
        }

        var shortcut: String {
            switch self {
            case .grid: return "G"
            case .edit: return "E"
            }
        }
    }

    var mode: Mode

    init(mode: Mode = .edit) {
        self.mode = mode
    }

    var isGrid: Bool { mode == .grid }
    var isEdit: Bool { mode == .edit }

    mutating func move(to mode: Mode) {
        self.mode = mode
    }
}
