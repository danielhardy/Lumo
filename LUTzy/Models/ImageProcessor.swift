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

    // MARK: - Supported formats (single source of truth)

    /// Canonical RAW file extensions (lowercased). RAW files are demosaiced via CIRAWFilter.
    /// Add a new RAW format here and it flows to RAW detection and `supportedExtensions`.
    private static let rawExtensions: Set<String> = [
        "dng", "cr2", "cr3", "nef", "arw", "orf",
        "raf", "rw2", "pef", "srw", "x3f", "raw",
    ]

    /// Canonical standard (non-RAW) image extensions (lowercased), loaded directly as a `CIImage`.
    /// Add a new standard format here and it flows to `supportedExtensions` and `supportedTypes`.
    private static let standardExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "bmp", "heic",
    ]

    /// Every extension LUTzy can open (RAW + standard, lowercased). The one definition
    /// shared by both the open panel and folder import — derive from it, never duplicate it.
    static let supportedExtensions: Set<String> = rawExtensions.union(standardExtensions)

    /// Image types for `NSOpenPanel`, derived from the canonical extension sets above.
    /// `.rawImage` covers every RAW format in a single type; standard extensions map to system UTTypes.
    static let supportedTypes: [UTType] = {
        let standardTypes = standardExtensions.compactMap { UTType(filenameExtension: $0) }
        return [.rawImage] + Set(standardTypes).sorted { $0.identifier < $1.identifier }
    }()

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

        if Self.rawExtensions.contains(ext) {
            return try loadRAW(from: url)
        } else {
            guard let image = CIImage(contentsOf: url) else {
                throw ImageError.cannotLoad(url.lastPathComponent)
            }
            return image
        }
    }

    /// Develop a RAW/DNG at **neutral / default `CIRAWFilter` settings** — no
    /// user develop adjustments are applied.
    ///
    /// This is the single source of truth for the "neutral baseline" RAW
    /// render. Both normal RAW loading (`loadRAW`) and LUT derivation
    /// (`RecipeExtractor`) develop RAWs through here, so the derive baseline
    /// can never drift from the render path and stays independent of any
    /// user-adjustable develop path. Returns `nil` if the file can't be decoded.
    static func developRAWNeutral(at url: URL) -> CIImage? {
        return CIRAWFilter(imageURL: url)?.outputImage
    }

    /// Load a RAW/DNG file using CIRAWFilter for proper demosaicing.
    private func loadRAW(from url: URL) throws -> CIImage {
        guard let output = Self.developRAWNeutral(at: url) else {
            throw ImageError.cannotLoad(url.lastPathComponent)
        }
        return output
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

    // MARK: - Histogram

    /// Compute a 256-bin per-channel histogram (R, G, B, and Rec.709 luma) of
    /// `ciImage`. The image is rendered to a downscaled RGBA8 buffer first —
    /// `maxDimension` caps the longest side so this stays cheap (~a few ms)
    /// even for full-resolution RAWs, while remaining representative.
    ///
    /// Safe to call off the main actor (uses the shared `CIContext`, which is
    /// thread-safe). Returns `nil` if the image has no renderable extent.
    func histogram(of ciImage: CIImage, maxDimension: Int = 512) -> HistogramData? {
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0,
              extent.width.isFinite, extent.height.isFinite else { return nil }

        let scale = min(
            CGFloat(maxDimension) / extent.width,
            CGFloat(maxDimension) / extent.height,
            1.0
        )
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rect = scaled.extent.integral
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            context.render(
                scaled,
                toBitmap: base,
                rowBytes: bytesPerRow,
                bounds: rect,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }

        var red = [Int](repeating: 0, count: 256)
        var green = [Int](repeating: 0, count: 256)
        var blue = [Int](repeating: 0, count: 256)
        var luma = [Int](repeating: 0, count: 256)

        bytes.withUnsafeBufferPointer { buf in
            for y in 0..<height {
                let row = y * bytesPerRow
                for x in 0..<width {
                    let off = row + x * 4
                    let r = Int(buf[off])
                    let g = Int(buf[off + 1])
                    let b = Int(buf[off + 2])
                    red[r] += 1
                    green[g] += 1
                    blue[b] += 1
                    // Rec.709 luma, rounded to nearest bin.
                    let l = (2126 * r + 7152 * g + 722 * b + 5000) / 10000
                    luma[min(255, l)] += 1
                }
            }
        }

        return HistogramData(red: red, green: green, blue: blue, luma: luma)
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
