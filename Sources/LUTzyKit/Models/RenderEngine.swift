import Foundation
import CoreImage
import CoreGraphics

/// What the app needs from a renderer, so a test can hand it something that is not the GPU.
///
/// The point of the protocol is not abstraction for its own sake — it is that once the view model
/// renders through this (Step 5), a test can drive the whole preview/export flow against a fake and
/// assert on *what was asked for* rather than on pixels. Pixel assertions belong to the engine's own
/// tests; everything above it should be testable without a Metal device.
///
/// `Sendable` because every conformer is crossed from the main actor. `actor RenderEngine` gets that
/// for free; a fake has to earn it.
protocol RenderEngining: Sendable {

    /// Rasterize `document` over `source` for display.
    ///
    /// Returns `sending` rather than a plain `CGImage?` because **`CGImage` is not `Sendable`**
    /// (verified against the SDK — there is no `@unchecked` conformance to lean on). Region-based
    /// isolation lets the freshly-created image leave the actor safely: the engine provably holds no
    /// other reference to it. The alternative — returning raw bytes and rebuilding a `CGImage` on the
    /// far side — would cost a copy of every preview frame to say the same thing.
    func makeCGImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace
    ) async -> sending CGImage?

    /// Encode `document` over `source` to a file format's bytes.
    ///
    /// Returns `Data` for the caller to write, rather than taking a URL. File I/O is not the GPU's
    /// business, and keeping it out means the actor never touches the sandbox, the security-scoped
    /// bookmark, or a partially-written file.
    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        format: ImageProcessor.ExportFormat,
        quality: CGFloat,
        space: WorkingSpace
    ) async throws -> Data

    /// Tally `document` over `source` into a 256-bin per-channel histogram.
    ///
    /// On the protocol rather than left to the caller because tallying needs a rasterizer, and the
    /// rasterizer is this actor. The alternative — handing the caller a `CIImage` to tally itself —
    /// is the old `ImageProcessor` shape, and it is what let the histogram describe a *different*
    /// image from the one on screen: it graded a full-resolution neutral decode with only the LUT,
    /// while the preview showed develop and adjustments too.
    ///
    /// `scale` should be the **display** scale, not a histogram-sized one, so the call reuses the
    /// engine's developed-source memo instead of evicting it; the tally buffer is capped separately
    /// by `maxDimension`.
    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        maxDimension: Int
    ) async -> HistogramData?
}

/// The one `CIContext`.
///
/// **The GPU is the isolation boundary** (`docs/PHASE2_SPEC.md` §4.5). `CIImage`, `CIFilter` and
/// `CIContext` are born and die inside this actor; only `Sendable` values cross in — `EditDocument`,
/// `ImageSource`, `CubeLUT`, `WorkingSpace`, `RenderScale` — and a `sending CGImage?` or a `Data`
/// crosses out. That is what lets Step 8 turn strict concurrency on without a single `@unchecked`.
///
/// It deliberately does **not** decide *what* to render. `RenderPipeline.buildImage` is a pure
/// function that builds the graph; this evaluates it. Preview and export call the same builder and
/// differ only in `scale`, which is what makes their agreement structural rather than maintained
/// (§1).
///
/// Added in Step 4 **alongside** the old `ImageProcessor` path. Both contexts exist for now; the app
/// still renders through the old one until Steps 5–7 cut over leaf by leaf and `ImageProcessor`'s GPU
/// duties are deleted.
actor RenderEngine: RenderEngining {

    /// The app's engine. One instance, therefore one context.
    static let shared = RenderEngine()

    private let context: CIContext

    /// Cube filters, reused across renders. Lives here rather than on `CubeLUT` because it is mutable
    /// reference state: a `CIFilter` gets its `inputImage` written on every use, so it is only safe
    /// behind this actor's serialization (§4.5).
    private let lutCache = LUTFilterCache()

    init() {
        // Matches `ImageProcessor`: Metal when there is a device, the CPU fallback when there isn't
        // (CI runners included).
        if let device = MTLCreateSystemDefaultDevice() {
            self.context = CIContext(mtlDevice: device)
        } else {
            self.context = CIContext()
        }
    }

    /// Inject a context — for tests that need to pin the backend rather than take whatever the
    /// machine offers.
    init(context: CIContext) {
        self.context = context
    }

    // MARK: - Rendering

    func makeCGImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace = .current
    ) -> sending CGImage? {
        guard let image = buildImage(source, document, lut, scale, space) else { return nil }
        let rect = image.extent.integral
        guard rect.isRasterizable else { return nil }

        // The colour space is passed explicitly — this is the output-encoding half of the seam, and
        // omitting it is exactly the latent preview/export mismatch Step 1 closed.
        return context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: space.cgColorSpace)
    }

    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale = .full,
        format: ImageProcessor.ExportFormat,
        quality: CGFloat = 0.95,
        space: WorkingSpace = .current
    ) throws -> Data {
        guard let image = buildImage(source, document, lut, scale, space) else {
            throw ImageError.processingFailed
        }
        guard image.extent.isRasterizable else {
            throw ImageError.processingFailed
        }
        let colorSpace = space.cgColorSpace

        switch format {
        case .tiff:
            guard let data = context.tiffRepresentation(
                of: image, format: .RGBA16, colorSpace: colorSpace
            ) else { throw ImageError.exportFailed }
            return data

        case .jpeg:
            guard let data = context.jpegRepresentation(
                of: image, colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
            ) else { throw ImageError.exportFailed }
            return data

        case .png:
            guard let data = context.pngRepresentation(
                of: image, format: .RGBA8, colorSpace: colorSpace
            ) else { throw ImageError.exportFailed }
            return data
        }
    }

    // MARK: - Histogram

    /// Tally the rendered document into 256 bins per channel.
    ///
    /// The image is rendered to a downscaled RGBA8 buffer first — `maxDimension` caps the longest
    /// side so this stays a few milliseconds even for a 60 MP source, while staying representative.
    ///
    /// `scale` is the caller's *display* scale on purpose. The developed-source memo is keyed on it
    /// (§6, "the cutover's one real trap"), so asking for a histogram at some private 512 px scale
    /// would evict the preview's entry on every tally and re-develop the RAW on the next frame —
    /// turning a cheap panel into a per-frame decode. Rendering the same graph the preview renders
    /// and shrinking only the tally buffer keeps both on one memo entry.
    ///
    /// The buffer is rendered in `space` for the same reason `makeCGImage` is: the histogram should
    /// describe the pixels the user is looking at, not a differently-encoded copy of them.
    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace = .current,
        maxDimension: Int = 512
    ) -> HistogramData? {
        guard maxDimension > 0, let image = buildImage(source, document, lut, scale, space) else {
            return nil
        }
        let extent = image.extent
        guard extent.isRasterizable else { return nil }

        let factor = min(
            CGFloat(maxDimension) / extent.width,
            CGFloat(maxDimension) / extent.height,
            1.0
        )
        let scaled = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        let rect = scaled.extent.integral
        guard rect.isRasterizable else { return nil }

        let width = Int(rect.width)
        let height = Int(rect.height)
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        bytes.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            context.render(
                scaled, toBitmap: base, rowBytes: bytesPerRow, bounds: rect,
                format: .RGBA8, colorSpace: space.cgColorSpace
            )
        }
        return HistogramData(rgba8: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    // MARK: - Cache

    /// Drop every cached cube filter. For a library rescan: a `LUTID` is a file path, so a `.cube`
    /// edited in place keeps its ID and would otherwise keep serving the old cube.
    func invalidateLUTCache() {
        lutCache.removeAll()
    }

    /// How many cube filters are held. Internal for the tests that prove the cache is actually being
    /// used across renders rather than rebuilt each time — there is no other way to observe it from
    /// outside, and a silently-bypassed cache is invisible in the output.
    var cachedFilterCount: Int { lutCache.count }

    // MARK: - Private

    /// One funnel, so preview and export cannot diverge in how they build the graph — only in the
    /// scale they ask for.
    private func buildImage(
        _ source: ImageSource,
        _ document: EditDocument,
        _ lut: CubeLUT?,
        _ scale: RenderScale,
        _ space: WorkingSpace
    ) -> CIImage? {
        guard let developed = developedSource(source, document.rawDevelop, scale) else { return nil }
        return RenderPipeline.buildImage(
            developed: developed, document: document, lut: lut, space: space, lutCache: lutCache
        )
    }

    // MARK: - The developed-source memo

    private struct DevelopedKey: Equatable {
        let source: ImageSource
        let rawDevelop: RAWDevelopSettings
        let scale: RenderScale
    }

    private var developedKey: DevelopedKey?
    private var developedImage: CIImage?

    /// The source stage, memoized for **preview** renders.
    ///
    /// This exists for one measured reason. Core Image caches decoded intermediates against the
    /// `CIImage` instance, so handing it a freshly-built source every render means re-decoding the
    /// file every render. Measured per preview render, rebuilding versus reusing:
    ///
    /// | source | rebuild | reuse |
    /// |---|---|---|
    /// | 30 MB DNG | 63 ms | 0.7 ms |
    /// | 6000×4000 | 156 ms | 0.6 ms |
    ///
    /// An intensity drag is many renders, so without this the cutover would be a plainly visible
    /// regression — the one thing Step 5 must not ship.
    ///
    /// **Only preview scales are memoized.** Export runs once per user action, so it has nothing to
    /// gain, and holding a full-resolution developed image between exports would pin Core Image's
    /// full-resolution intermediates for as long as the engine lives.
    ///
    /// A single entry, because the user is looking at one image at a time: changing image, develop
    /// settings, or preview size replaces it. Nothing is retained once the next image is opened.
    private func developedSource(
        _ source: ImageSource,
        _ rawDevelop: RAWDevelopSettings,
        _ scale: RenderScale
    ) -> CIImage? {
        guard case .preview = scale else {
            return RenderPipeline.developedSource(source, rawDevelop: rawDevelop, scale: scale)
        }
        let key = DevelopedKey(source: source, rawDevelop: rawDevelop, scale: scale)
        if key == developedKey, let developedImage { return developedImage }

        guard let image = RenderPipeline.developedSource(
            source, rawDevelop: rawDevelop, scale: scale
        ) else { return nil }

        developedKey = key
        developedImage = image
        return image
    }

    /// Drop the developed-source memo. Not needed for correctness — the key covers every input — but
    /// it lets a caller release the intermediates when no image is on screen.
    func invalidateSourceCache() {
        developedKey = nil
        developedImage = nil
    }
}
