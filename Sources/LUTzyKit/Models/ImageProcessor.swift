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
    static let rawExtensions: Set<String> = [
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

    /// Load any supported image file as a CIImage, upright.
    func loadImage(from url: URL) throws -> CIImage {
        let ext = url.pathExtension.lowercased()

        if Self.rawExtensions.contains(ext) {
            return try loadRAW(from: url)
        } else {
            guard let image = CIImage(contentsOf: url, options: Self.orientedLoadOptions) else {
                throw ImageError.cannotLoad(url.lastPathComponent)
            }
            return image
        }
    }

    /// Load in-memory image data (Photos imports, drag-and-drop payloads) as an
    /// upright CIImage.
    func loadImage(from data: Data, name: String) throws -> CIImage {
        guard let image = CIImage(data: data, options: Self.orientedLoadOptions) else {
            throw ImageError.cannotLoad(name)
        }
        return image
    }

    /// Decode options that bake a file's EXIF orientation into the returned
    /// image's geometry.
    ///
    /// `CIImage` does **not** honor the orientation tag by default, but
    /// `CIRAWFilter` does and so does the thumbnail path
    /// (`kCGImageSourceCreateThumbnailWithTransform`). Without this a portrait
    /// JPEG/HEIC previewed *and exported* on its side while its filmstrip
    /// thumbnail stood upright. Every non-RAW decode in the app goes through
    /// these options so all three paths agree.
    /// Computed rather than stored: a `static let` of `[CIImageOption: Any]` is shared mutable state
    /// as far as the compiler is concerned (`Any` is not `Sendable`), which is a warning today and an
    /// error under Swift 6. `RenderPipeline` reads this from inside `actor RenderEngine`, so the fix
    /// belongs with the code that made it load-bearing rather than with Step 8. Rebuilding a
    /// one-entry dictionary is free next to decoding an image.
    static var orientedLoadOptions: [CIImageOption: Any] { [.applyOrientationProperty: true] }

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
    ///
    /// The `space` argument is passed explicitly to `createCGImage`. It used to be omitted, which
    /// meant the preview rasterized through the `CIContext` default while `export` forced sRGB —
    /// byte-identical while everything was sRGB, and a silent divergence the moment it wasn't.
    func renderPreview(_ ciImage: CIImage, maxSize: CGSize, space: WorkingSpace = .current) -> NSImage? {
        let extent = ciImage.extent
        guard extent.isRasterizable else { return nil }

        let scale = min(
            maxSize.width / extent.width,
            maxSize.height / extent.height,
            1.0
        )
        let outputWidth = Int(extent.width * scale)
        let outputHeight = Int(extent.height * scale)

        // Scale down via Core Image for quality
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(
            scaled, from: scaled.extent, format: .RGBA8, colorSpace: space.cgColorSpace
        ) else {
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
    func renderToNSImage(_ ciImage: CIImage, space: WorkingSpace = .current) -> NSImage? {
        let extent = ciImage.extent
        guard extent.isRasterizable else { return nil }
        guard let cgImage = context.createCGImage(
            ciImage, from: extent, format: .RGBA8, colorSpace: space.cgColorSpace
        ) else { return nil }
        return NSImage(cgImage: cgImage, size: extent.size)
    }

    // MARK: - Export

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

    /// Export a CIImage to a file at full resolution.
    func export(
        _ ciImage: CIImage,
        to url: URL,
        format: ExportFormat,
        quality: CGFloat = 0.95,
        space: WorkingSpace = .current
    ) throws {
        guard ciImage.extent.isRasterizable else {
            throw ImageError.processingFailed
        }

        // The output-encoding half of the colour seam. Must be the same
        // WorkingSpace the LUT interpolated in — see WorkingSpace.
        let colorSpace = space.cgColorSpace

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

// MARK: - Extent

extension CGRect {
    /// Whether this extent can actually be turned into a pixel buffer.
    ///
    /// Rejects empty, null, and — the one that bites — **infinite** extents.
    /// `CGRect.infinite` is built from `greatestFiniteMagnitude`, not `inf`, so
    /// an `isFinite` check on its width passes while `Int(width)` traps at
    /// runtime. Generator-backed images (`CIImage(color:)` and friends) have
    /// exactly that extent, so any code path that might meet one has to test
    /// `isInfinite` explicitly.
    var isRasterizable: Bool {
        !isInfinite && !isNull && !isEmpty
            && width.isFinite && height.isFinite
            && width >= 1 && height >= 1
    }
}

// MARK: - Errors

enum ImageError: LocalizedError, Sendable {
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
