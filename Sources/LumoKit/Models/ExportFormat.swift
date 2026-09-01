import Foundation
import UniformTypeIdentifiers

/// The file formats Lumo writes.
///
/// Promoted out of `ImageProcessor` in Step 7, when that type dissolved. `docs/PHASE2_SPEC.md` §7
/// flagged the promotion as a risk worth carrying deliberately: the export flow presents
/// `allCases` and keys format choices by `id`, while `NSSavePanel` seeds its filename from
/// `fileExtension`. Dropping `Identifiable` or changing the raw values would break both — quietly,
/// because a picker with duplicate or missing IDs still compiles. So `CaseIterable`, `Identifiable`,
/// `Sendable` and the exact raw strings all remain part of the export-format contract.
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
