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
enum ExportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case tiff = "TIFF"
    case jpeg = "JPEG"
    case png  = "PNG"
    case heif = "HEIF"

    var id: String { rawValue }

    var utType: UTType {
        switch self {
        case .tiff: return .tiff
        case .jpeg: return .jpeg
        case .png:  return .png
        case .heif: return .heic
        }
    }

    var fileExtension: String {
        switch self {
        case .tiff: return "tif"
        case .jpeg: return "jpg"
        case .png:  return "png"
        case .heif: return "heic"
        }
    }

    var capabilities: ExportFormatCapabilities {
        switch self {
        case .tiff:
            return ExportFormatCapabilities(
                bitDepths: [.eight, .sixteen],
                colorSpaces: [.sRGB, .displayP3],
                alphaModes: [.opaque, .preserve]
            )
        case .jpeg:
            return ExportFormatCapabilities(
                bitDepths: [.eight],
                colorSpaces: [.sRGB, .displayP3],
                alphaModes: [.opaque]
            )
        case .png:
            return ExportFormatCapabilities(
                bitDepths: [.eight, .sixteen],
                colorSpaces: [.sRGB, .displayP3],
                alphaModes: [.opaque, .preserve]
            )
        case .heif:
            // Image I/O's HEIC writer is a hardware-backed HEVC encoder on supported Macs. Keep
            // the advertised contract to the combination that has a deterministic round trip:
            // 8-bit, opaque output in either supported working space. If the encoder is absent,
            // CGImageDestination reports the failure and the export coordinator isolates it to
            // the current item.
            return ExportFormatCapabilities(
                bitDepths: [.eight],
                colorSpaces: [.sRGB, .displayP3],
                alphaModes: [.opaque]
            )
        }
    }

    var defaultBitDepth: ExportBitDepth {
        self == .tiff ? .sixteen : .eight
    }

    var defaultAlpha: ExportAlpha {
        self == .jpeg || self == .heif ? .opaque : .preserve
    }
}
