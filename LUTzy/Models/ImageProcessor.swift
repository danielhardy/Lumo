import Foundation
import CoreImage
import AppKit
import UniformTypeIdentifiers
import ImageIO

/// Handles RAW/DNG and standard image loading, LUT application, and export
/// using Core Image for hardware-accelerated processing.
final class ImageProcessor {

    static let shared = ImageProcessor()

    private let context: CIContext

    /// All image types we can open.
    static let supportedTypes: [UTType] = [
        .rawImage,
        .jpeg, .png, .tiff, .bmp, .heic,
    ]

    /// RAW-specific types (need CIRAWFilter).
    private static let rawTypes: Set<String> = [
        "dng", "cr2", "cr3", "nef", "arw", "orf",
        "raf", "rw2", "pef", "srw", "x3f", "raw",
    ]

    private init() {
        // Use Metal for GPU acceleration when available.
        if let device = MTLCreateSystemDefaultDevice() {
            self.context = CIContext(mtlDevice: device)
        } else {
            self.context = CIContext()
        }
    }

    // MARK: - Loading

    /// Load any supported image file as a CIImage.
    func loadImage(from url: URL) throws -> CIImage {
        let ext = url.pathExtension.lowercased()

        if Self.rawTypes.contains(ext) {
            return try loadRAW(from: url)
        } else {
            guard let image = CIImage(contentsOf: url) else {
                throw ImageError.cannotLoad(url.lastPathComponent)
            }
            return image
        }
    }

    /// Load a RAW/DNG file using CIRAWFilter for proper demosaicing.
    private func loadRAW(from url: URL) throws -> CIImage {
        if #available(macOS 12.0, *) {
            guard let filter = CIRAWFilter(imageURL: url) else {
                throw ImageError.cannotLoad(url.lastPathComponent)
            }
            guard let output = filter.outputImage else {
                throw ImageError.processingFailed
            }
            return output
        } else {
            // Fallback for older macOS
            guard let filter = CIFilter(imageURL: url, options: nil) else {
                throw ImageError.cannotLoad(url.lastPathComponent)
            }
            guard let output = filter.outputImage else {
                throw ImageError.processingFailed
            }
            return output
        }
    }

    // MARK: - Preview rendering

    /// Render a CIImage to an NSImage at the given maximum size.
    func renderPreview(_ ciImage: CIImage, maxSize: CGSize) -> NSImage? {
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let scale = min(
            maxSize.width / extent.width,
            maxSize.height / extent.height,
            1.0
        )
        let outputWidth = Int(extent.width * scale)
        let outputHeight = Int(extent.height * scale)

        // Scale down via Core Image for quality
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: outputWidth, height: outputHeight))
    }

    // MARK: - Thumbnails

    /// Generate a thumbnail quickly using CGImageSource (uses embedded JPEG for RAW files).
    func generateThumbnail(from url: URL, maxPixelSize: Int = 240) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnailFromSource(source, maxPixelSize: maxPixelSize)
    }

    /// Generate a thumbnail from in-memory data (for Photos imports).
    func generateThumbnail(from data: Data, maxPixelSize: Int = 240) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnailFromSource(source, maxPixelSize: maxPixelSize)
    }

    private func thumbnailFromSource(_ source: CGImageSource, maxPixelSize: Int) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Render to NSImage at full extent (for small images / previews).
    func renderToNSImage(_ ciImage: CIImage) -> NSImage? {
        let extent = ciImage.extent
        guard let cgImage = context.createCGImage(ciImage, from: extent) else { return nil }
        return NSImage(cgImage: cgImage, size: extent.size)
    }

    // MARK: - Export

    enum ExportFormat: String, CaseIterable, Identifiable {
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

    /// Export a CIImage to a file at full resolution.
    func export(_ ciImage: CIImage, to url: URL, format: ExportFormat, quality: CGFloat = 0.95) throws {
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else {
            throw ImageError.processingFailed
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        switch format {
        case .tiff:
            // 16-bit TIFF
            guard let data = context.tiffRepresentation(
                of: ciImage,
                format: .RGBA16,
                colorSpace: colorSpace
            ) else {
                throw ImageError.exportFailed
            }
            try data.write(to: url)

        case .jpeg:
            guard let data = context.jpegRepresentation(
                of: ciImage,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
            ) else {
                throw ImageError.exportFailed
            }
            try data.write(to: url)

        case .png:
            guard let data = context.pngRepresentation(
                of: ciImage,
                format: .RGBA8,
                colorSpace: colorSpace
            ) else {
                throw ImageError.exportFailed
            }
            try data.write(to: url)
        }
    }
}

// MARK: - Errors

enum ImageError: LocalizedError {
    case cannotLoad(String)
    case processingFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .cannotLoad(let name): return "Cannot load \(name)"
        case .processingFailed: return "Image processing failed"
        case .exportFailed: return "Export failed"
        }
    }
}
