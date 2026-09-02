import Foundation
import CoreGraphics

/// The work a renderer should perform.
///
/// This is deliberately made only from value types. It is safe to create on the main actor and
/// send to a renderer without bringing SwiftUI, AppKit, `CIImage`, or a file destination into the
/// rendering API. `document` is the one edit model for every quality tier.
/// The representation a render should return.
enum RenderOutput: Sendable, Equatable {
    /// Return a displayable lossless raster (PNG) in the requested working space.
    case raster
    /// Return bytes in the requested export format and encoder quality.
    case encoded(format: ExportFormat, quality: CGFloat)

    /// A descriptive alias for callers that think in terms of display images.
    static var image: Self { .raster }
}

struct RenderRequest: Sendable, Equatable {
    /// Kept nested as a discoverable spelling alongside the top-level type.
    typealias Output = RenderOutput

    let source: ImageSource
    let document: EditDocument
    let lut: CubeLUT?
    /// Maximum output dimensions for preview tiers. Export sizing is carried by exportOptions.
    let targetSize: CGSize?
    let quality: RenderQuality
    let frameBudgetMilliseconds: Double
    let output: Output
    let space: WorkingSpace
    /// Full export policy when this is an encoded request. Kept separate from `RenderOutput` so the
    /// legacy format/quality spelling remains source-compatible for existing renderer clients.
    let exportOptions: ExportOptions?

    init(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT? = nil,
        targetSize: CGSize? = nil,
        quality: RenderQuality,
        frameBudgetMilliseconds: Double = 16.7,
        output: Output = .raster,
        space: WorkingSpace = .current,
        exportOptions: ExportOptions? = nil
    ) {
        self.source = source
        self.document = document
        self.lut = lut
        self.targetSize = targetSize
        self.quality = quality
        self.frameBudgetMilliseconds = frameBudgetMilliseconds
        self.output = output
        self.space = space
        self.exportOptions = exportOptions
    }

    /// The scale policy used by the existing deterministic pipeline.
    ///
    /// Downsampled quality tiers intentionally share the same source/edit pipeline. Their quality
    /// identity remains visible in the request so a future scheduler or cache can distinguish them,
    /// while the current implementation uses the requested viewport as the only pixel policy.
    var renderScale: RenderScale {
        switch quality {
        case .thumbnail, .preview:
            return .preview(maxSize: targetSize ?? source.nativeExtent)
        case .interactive:
            return .interactive(
                maxSize: targetSize ?? source.nativeExtent,
                frameBudgetMilliseconds: frameBudgetMilliseconds
            )
        case .fullResolution:
            return .full
        case .export:
            guard let options = exportOptions, options.sizing.longEdge != nil else {
                return .full
            }
            // Use the durable pixel plan as the render box. RenderScale applies the tightest
            // axis and the renderer's integral extent rounds outward, so bounding the unrounded
            // image by these planned dimensions makes the encoded pixels match outputSize(for:).
            return .preview(maxSize: options.outputSize(for: source.nativeExtent))
        }
    }
}

/// The five work classes used by orchestration and caching.
///
/// Quality is intentionally independent from `RenderRequest.Output`: an interactive raster and an
/// export encoding are different output policies, while both still use the same `EditDocument` and
/// deterministic adjustment/LUT ordering.
enum RenderQuality: String, Codable, CaseIterable, Sendable, Equatable {
    case thumbnail
    case interactive
    case preview
    case fullResolution
    case export
}

/// A renderer's sendable response.
///
/// Raster results are PNG bytes, not `CGImage`: Core Graphics image objects are not Sendable and must
/// stay inside the renderer actor. The extent is the integral pixel extent actually encoded, and the
/// color space records the same `WorkingSpace` used for LUT interpolation and output encoding.
struct RenderResult: Sendable, Equatable {
    let data: Data
    let extent: CGSize
    let colorSpace: WorkingSpace
    let quality: RenderQuality
    let output: RenderOutput

    var imageData: Data { data }

    init(
        data: Data,
        extent: CGSize,
        colorSpace: WorkingSpace,
        quality: RenderQuality,
        output: RenderOutput
    ) {
        self.data = data
        self.extent = extent
        self.colorSpace = colorSpace
        self.quality = quality
        self.output = output
    }
}
