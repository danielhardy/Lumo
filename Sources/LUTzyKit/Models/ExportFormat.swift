import Foundation
import UniformTypeIdentifiers

/// The file formats LUTzy writes.
///
/// Promoted out of `ImageProcessor` in Step 7, when that type dissolved. `docs/PHASE2_SPEC.md` §7
/// flagged the promotion as a risk worth carrying deliberately: the toolbar `Picker` iterates
/// `allCases` and keys rows by `id`, and `NSSavePanel` seeds its filename from `rawValue` via
/// `fileExtension`. Dropping `Identifiable` or changing the raw values would break both — quietly,
/// because a `Picker` with duplicate or missing IDs still compiles. So `CaseIterable`,
/// `Identifiable`, `Sendable` and the exact raw strings all come across unchanged, and the move
/// happens in one commit with every reference updated.
enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case tiff = "TIFF"
    case jpeg = "JPEG"
    case png  = "PNG"

    var id: String { rawValue }

    var utType: UTType {
        switch self {
        case .tiff: return .tiff
        case .jpeg: return .jpeg
        case .png:  return .png
        }
    }

    var fileExtension: String {
        switch self {
        case .tiff: return "tif"
        case .jpeg: return "jpg"
        case .png:  return "png"
        }
    }
}
