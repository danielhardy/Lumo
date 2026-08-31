import Foundation

/// The culling filters applied to every library browsing surface.
///
/// Flag and rating filters are independent and are combined with AND semantics. Keeping this as a
/// value type makes the filtering rules deterministic and easy to exercise without SwiftUI.
enum LibraryFlagFilter: String, CaseIterable, Codable, Sendable {
    case all
    case picks
    case rejected

    var title: String {
        switch self {
        case .all: "All"
        case .picks: "Picks"
        case .rejected: "Rejected"
        }
    }
}

enum LibraryRatingFilter: Codable, Equatable, Hashable, Sendable {
    case any
    case minimum(Int)
    case exact(Int)

    static let allValues: [LibraryRatingFilter] = [.any]
        + (1...5).map { .minimum($0) }
        + (0...5).map { .exact($0) }

    var title: String {
        switch self {
        case .any: "Any rating"
        case .minimum(let rating): "\(rating)+ stars"
        case .exact(let rating): "Exactly \(rating) stars"
        }
    }

    func matches(_ rating: Int) -> Bool {
        switch self {
        case .any: true
        case .minimum(let minimum): rating >= minimum
        case .exact(let exact): rating == exact
        }
    }
}

struct LibraryFilter: Codable, Equatable, Hashable, Sendable {
    var flag: LibraryFlagFilter = .all
    var rating: LibraryRatingFilter = .any

    static let all = LibraryFilter()

    var isFiltered: Bool { flag != .all || rating != .any }

    func matches(flag assetFlag: PhotoFlag, rating assetRating: Int) -> Bool {
        let flagMatches: Bool
        switch flag {
        case .all: flagMatches = true
        case .picks: flagMatches = assetFlag == .pick
        case .rejected: flagMatches = assetFlag == .reject
        }
        return flagMatches && rating.matches(assetRating)
    }
}

/// Character-level culling routing kept separate from NSEvent handling so the shortcut contract can
/// be tested without constructing an AppKit event or a window.
enum LibraryCullingCommand: Equatable, Sendable {
    case pick
    case reject
    case clearRating
    case rating(Int)

    static func parse(characters: String, hasModifiers: Bool = false) -> LibraryCullingCommand? {
        guard !hasModifiers else { return nil }
        switch characters.lowercased() {
        case "p": return .pick
        case "x": return .reject
        case "0": return .clearRating
        case "1": return .rating(1)
        case "2": return .rating(2)
        case "3": return .rating(3)
        case "4": return .rating(4)
        case "5": return .rating(5)
        default: return nil
        }
    }
}
