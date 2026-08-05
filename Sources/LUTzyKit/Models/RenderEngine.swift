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
        RenderPipeline.buildImage(
            source: source, document: document, lut: lut,
            scale: scale, space: space, lutCache: lutCache
        )
    }
}
