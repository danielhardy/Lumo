import Foundation
import CoreGraphics

/// The precision requested from an export encoder.
enum ExportBitDepth: Int, Codable, CaseIterable, Sendable, Equatable {
    case eight = 8
    case sixteen = 16
}

/// Whether an export may carry transparent pixels.
enum ExportAlpha: String, Codable, CaseIterable, Sendable, Equatable {
    case opaque
    case preserve
}

/// How much of the source is written. Source extents are upright/display-oriented.
enum ExportSizing: Codable, Sendable, Equatable {
    case fullSize
    case longEdge(Int)

    var longEdge: Int? {
        guard case .longEdge(let edge) = self else { return nil }
        return edge
    }

    /// The requested output dimensions, preserving orientation and aspect ratio.
    /// A long-edge export never upscales a source.
    func outputSize(for sourceExtent: CGSize) -> CGSize {
        guard sourceExtent.width.isFinite, sourceExtent.height.isFinite,
              sourceExtent.width > 0, sourceExtent.height > 0 else { return .zero }
        guard case .longEdge(let requestedEdge) = self, requestedEdge > 0 else {
            return sourceExtent
        }

        let sourceLongEdge = max(sourceExtent.width, sourceExtent.height)
        let factor = min(1, CGFloat(requestedEdge) / sourceLongEdge)
        return CGSize(
            width: max(1, (sourceExtent.width * factor).rounded(.toNearestOrAwayFromZero)),
            height: max(1, (sourceExtent.height * factor).rounded(.toNearestOrAwayFromZero))
        )
    }

}

/// The destination is represented as data so export options do not depend on an AppKit panel.
enum ExportDestination: Codable, Sendable, Equatable {
    case file(URL)
    case folder(URL)
}

/// Naming policy shared by single and batch exports.
enum ExportFilenamePolicy: String, Codable, CaseIterable, Sendable, Equatable {
    case sourceName
    case sourceNameWithLook

    func baseName(source: String, look: String?) -> String {
        guard self == .sourceNameWithLook, let look, !look.isEmpty else { return source }
        return source + "_" + look.replacingOccurrences(of: " ", with: "_")
    }
}

/// Metadata handling is explicit even when the source has no metadata to copy.
enum ExportMetadataPolicy: String, Codable, CaseIterable, Sendable, Equatable {
    case preserve
    case strip
}

/// The formats and encoder constraints supported by the current Core Image path.
struct ExportFormatCapabilities: Codable, Sendable, Equatable {
    let bitDepths: [ExportBitDepth]
    let colorSpaces: [WorkingSpace]
    let alphaModes: [ExportAlpha]

    var supportedBitDepths: [ExportBitDepth] { bitDepths }
    var supportedColorSpaces: [WorkingSpace] { colorSpaces }
    var supportedAlphaModes: [ExportAlpha] { alphaModes }
    var supportsAlpha: Bool { alphaModes.contains(.preserve) }

    func supports(bitDepth: ExportBitDepth, colorSpace: WorkingSpace, alpha: ExportAlpha) -> Bool {
        bitDepths.contains(bitDepth) && colorSpaces.contains(colorSpace) && alphaModes.contains(alpha)
    }
}

/// A complete, panel-independent export description.
///
/// This is intentionally value-only and Codable: a coordinator can persist or queue it without
/// carrying NSSavePanel, CIImage, or any other UI/rendering object across an actor boundary.
struct ExportOptions: Codable, Sendable, Equatable {
    let format: ExportFormat
    let quality: Double
    let sizing: ExportSizing
    let colorSpace: WorkingSpace
    let bitDepth: ExportBitDepth
    let alpha: ExportAlpha
    let filenamePolicy: ExportFilenamePolicy
    let destination: ExportDestination?
    let metadata: ExportMetadataPolicy
    /// Optional post-export delivery. The file/folder destination is committed first.
    let photos: PhotosExportOptions?

    init(
        format: ExportFormat = .jpeg,
        quality: Double = 0.95,
        sizing: ExportSizing = .fullSize,
        colorSpace: WorkingSpace = .current,
        bitDepth: ExportBitDepth? = nil,
        alpha: ExportAlpha? = nil,
        filenamePolicy: ExportFilenamePolicy = .sourceNameWithLook,
        destination: ExportDestination? = nil,
        metadata: ExportMetadataPolicy = .preserve,
        photos: PhotosExportOptions? = nil
    ) {
        self.format = format
        self.quality = quality
        self.sizing = sizing
        self.colorSpace = colorSpace
        self.bitDepth = bitDepth ?? format.defaultBitDepth
        self.alpha = alpha ?? format.defaultAlpha
        self.filenamePolicy = filenamePolicy
        self.destination = destination
        self.metadata = metadata
        self.photos = photos
    }

    static let `default` = ExportOptions()

    func validate() throws {
        guard quality.isFinite, (0...1).contains(quality) else {
            throw ExportOptionsError.invalidQuality(quality)
        }
        if case .longEdge(let edge) = sizing, edge <= 0 {
            throw ExportOptionsError.invalidLongEdge(edge)
        }
        try validateFormatCombination()
    }

    private func validateFormatCombination() throws {
        let capabilities = format.capabilities
        guard capabilities.bitDepths.contains(bitDepth) else {
            throw ExportOptionsError.unsupportedBitDepth(format: format, bitDepth: bitDepth)
        }
        guard capabilities.colorSpaces.contains(colorSpace) else {
            throw ExportOptionsError.unsupportedColorSpace(format: format, colorSpace: colorSpace)
        }
        guard capabilities.alphaModes.contains(alpha) else {
            throw ExportOptionsError.unsupportedAlpha(format: format, alpha: alpha)
        }
    }

    func fileName(source: String, look: String? = nil) -> String {
        filenamePolicy.baseName(source: source, look: look) + "." + format.fileExtension
    }

    func outputSize(for sourceExtent: CGSize) -> CGSize {
        sizing.outputSize(for: sourceExtent)
    }
}

enum ExportOptionsError: LocalizedError, Codable, Sendable, Equatable {
    case invalidQuality(Double)
    case invalidLongEdge(Int)
    case outputRequiresEncoded(expected: ExportFormat)
    case outputFormatMismatch(expected: ExportFormat, actual: ExportFormat)
    case unsupportedBitDepth(format: ExportFormat, bitDepth: ExportBitDepth)
    case unsupportedColorSpace(format: ExportFormat, colorSpace: WorkingSpace)
    case unsupportedAlpha(format: ExportFormat, alpha: ExportAlpha)

    var errorDescription: String? {
        switch self {
        case .invalidQuality(let quality):
            return "Export quality must be between 0 and 1 (received \(quality))."
        case .invalidLongEdge(let edge):
            return "Export long edge must be greater than zero (received \(edge) px)."
        case .outputRequiresEncoded(let expected):
            return "Export options request \(expected.rawValue), but the render output is raster; export options require encoded output."
        case .outputFormatMismatch(let expected, let actual):
            return "Export options request \(expected.rawValue), but the render requested \(actual.rawValue)."
        case .unsupportedBitDepth(let format, let bitDepth):
            return "\(format.rawValue) does not support \(bitDepth.rawValue)-bit output."
        case .unsupportedColorSpace(let format, let colorSpace):
            return "\(format.rawValue) does not support the \(colorSpace.rawValue) color space."
        case .unsupportedAlpha(let format, let alpha):
            return "\(format.rawValue) does not support \(alpha.rawValue) alpha output."
        }
    }
}
