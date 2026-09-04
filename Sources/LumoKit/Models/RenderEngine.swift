import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import Metal
import UniformTypeIdentifiers

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

    /// Prepare source value state without requesting source pixels. The production renderer owns
    /// RAW preparation so the same decoder session can answer geometry/capability questions and
    /// later develop the visible image.
    func prepareSource(_ source: ImageSource) async -> ImageSourcePreparation?

    /// Completed Core Image output for the persistent GPU presentation surface.
    ///
    /// A production implementation must not return a lazy source graph here. The returned image
    /// is backed by a completed GPU texture, so the caller may apply presentation-only transforms
    /// without causing source development or adjustment evaluation on its actor.
    func makeCIImage(_ request: RenderRequest) async -> sending CIImage?

    /// Render one UI-independent request through the deterministic pipeline.
    func render(_ request: RenderRequest) async throws -> RenderResult

    /// Produce a display image for a request without changing the Sendable render-result boundary.
    ///
    /// The default keeps conformers that only implement `render` source-compatible. The real
    /// engine overrides this with an actor-local `CIContext.createCGImage` path so interactive
    /// preview frames do not pay for an encoded PNG that is immediately decoded again.
    func makeCGImage(_ request: RenderRequest) async -> sending CGImage?

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

    /// Drop every cached cube filter, because the bytes behind a `LUTID` may have changed.
    ///
    /// **On the protocol as of Step 9, so that the app calling it is assertable.** The engine has had
    /// this method since Step 4 and it was correct the whole time; the only caller was a test, and
    /// nothing above the actor could see whether it fired. Its absence became reachable in Step 9:
    /// saving a second derive over the same `.cube` path yields the same `LUTID`, so without this the
    /// cache keeps serving the first cube and the second save silently does nothing on screen.
    func invalidateLUTCache() async

    /// What this source's RAW decoder can do, and where its own defaults sit. `nil` for a non-RAW.
    ///
    /// On the protocol because the develop inspector needs it and cannot reach a `CIRAWFilter`:
    /// the flags live on a non-`Sendable` type confined to the actor (§4.5). Returning a value is
    /// the only way the panel can be gated on what the decoder actually supports.
    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities?
}

/// Actor-local counters used by performance captures to separate RAW configuration, decoder output
/// requests, and completed prefix work. They are diagnostics only and do not affect cache identity.
struct RenderWorkStatistics: Sendable, Equatable {
    let rawFilterConstructions: Int
    let rawPropertyWrites: Int
    let rawOutputRequests: Int
    let processingPrefixMaterializations: Int
}

extension RenderEngining {
    func prepareSource(_ source: ImageSource) async -> ImageSourcePreparation? {
        guard source.kind == .standard else { return nil }
        let extent: CGSize?
        switch source.backing {
        case .url(let url):
            extent = try? ImageDecoder.prepareStandard(from: url)
        case .data(let data):
            extent = try? ImageDecoder.prepareStandard(from: data, name: "import")
        }
        guard let extent else { return nil }
        return ImageSourcePreparation(source: ImageSource(
            backing: source.backing, kind: source.kind, nativeExtent: extent
        ))
    }

    func makeCIImage(_ request: RenderRequest) async -> sending CIImage? { nil }

    func makeCGImage(_ request: RenderRequest) async -> sending CGImage? {
        guard request.output == .raster,
              let result = try? await render(request),
              let imageSource = CGImageSourceCreateWithData(result.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { return nil }
        return image
    }

    func makeCGImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace = .current
    ) async -> sending CGImage? {
        let request = RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: scale.targetSize,
            quality: scale == .full ? .fullResolution : .preview,
            output: .raster, space: space
        )
        return await makeCGImage(request)
    }

    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale = .full,
        format: ExportFormat,
        quality: CGFloat = 0.95,
        space: WorkingSpace = .current
    ) async throws -> Data {
        let request = RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: scale.targetSize,
            quality: scale == .full ? .export : .preview,
            output: .encoded(format: format, quality: quality), space: space
        )
        return try await render(request).data
    }

    /// Encode with the complete durable export policy, without involving a panel or destination I/O.
    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions
    ) async throws -> Data {
        try options.validate()
        return try await render(RenderRequest(
            source: source,
            document: document,
            lut: lut,
            quality: .export,
            output: .encoded(
                format: options.format,
                quality: CGFloat(options.quality)
            ),
            space: options.colorSpace,
            exportOptions: options
        )).data
    }
}

/// The render contexts have deliberately separate ownership domains. The processing context and
/// queue live behind `RenderEngine`; the presentation context and queue live on the main actor in
/// `PreviewSurfaceView.Coordinator`. They share a device, but neither context or queue crosses an
/// actor boundary. This prevents drawable acquisition/presentation from becoming part of source
/// evaluation while making the device/queue relationship explicit.
///
/// **The GPU is the isolation boundary** (`docs/PHASE2_SPEC.md` §4.5). Source graphs, filters and
/// processing contexts are born and die inside this actor; only value requests and completed,
/// texture-backed preview images cross out. That is what lets Step 8 turn strict concurrency on
/// without a single `@unchecked`.
///
/// It deliberately does **not** decide *what* to render. `RenderPipeline.buildImage` is a pure
/// function that builds the graph; this evaluates it. Preview and export call the same builder and
/// differ only in explicit quality/output policy, which is what makes their agreement structural
/// rather than maintained (§1).
///
/// Added in Step 4 **alongside** the old `ImageProcessor` path, which Steps 5–7 then cut over leaf by
/// leaf — preview, export, histogram — until nothing was left of it to delete. `RecipeExtractor`
/// keeps its own context by design (§3): it sits outside this stack, never imports `EditDocument`,
/// and samples in a space pinned to sRGB regardless of `WorkingSpace.current`. The render stack now
/// has one actor-owned processing context and one explicitly main-actor-owned presentation context;
/// `RenderStackTests` continues to protect against accidental context proliferation.
actor RenderEngine: RenderEngining {

    /// Shared device for the two explicitly-owned GPU domains. The engine's processing context is
    /// created from its private queue; the presentation context is created from the main-actor
    /// presentation queue below. A device is safe to share; mutable contexts and queues are not.
    @MainActor static let presentationDevice: MTLDevice = MTLCreateSystemDefaultDevice()!

    @MainActor static let presentationQueue: MTLCommandQueue = presentationDevice.makeCommandQueue()!
    @MainActor static let presentationContext: CIContext = CIContext(mtlCommandQueue: presentationQueue)

    func makeCIImage(_ request: RenderRequest) async -> sending CIImage? {
        guard request.output == .raster, !Task.isCancelled else { return nil }
        guard let image = buildImage(request.source, request.document, request.lut,
                                     request.renderScale, request.space, quality: request.quality),
              image.extent.isRasterizable
        else {
            return nil
        }
        guard let device, let commandQueue else {
            // This is the CPU/no-device compatibility seam. The shipping macOS path has a Metal
            // device and therefore takes the completed-texture path below; keeping the lazy image
            // available here preserves RenderEngine's graph-only test initializer and CPU CI hosts.
            return image
        }

        let rect = image.extent.integral
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard width > 0, height > 0,
              let texture = makePreviewTexture(device: device, width: width, height: height)
        else { return nil }

        // RGBAh/RGBA16Float is intentional. The processing result is never quantized to RGBA8
        // merely to cross the actor boundary; color matching and premultiplied-alpha behavior stay
        // in Core Image at the requested working-space precision. Core Image encodes into this
        // engine-owned command buffer, and the renderer does not hand the texture to presentation
        // until its completion handler reports success.
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        context.render(image, to: texture, commandBuffer: commandBuffer, bounds: rect,
                       colorSpace: request.space.cgColorSpace)
        guard await commitAndWaitForCompletion(commandBuffer), !Task.isCancelled else { return nil }
        // CIImage retains the texture. Since this image is only returned after the command buffer
        // completes, a presentation transform can sample it without racing an in-flight write.
        return CIImage(mtlTexture: texture, options: [.colorSpace: request.space.cgColorSpace])
    }

    /// The app's engine. One instance, therefore one actor-owned processing context and queue.
    static let shared = RenderEngine()

    /// All non-Sendable GPU and cache resources live in this actor-confined storage boundary.
    private let resources: RenderEngineResources

    // These narrow aliases keep the render algorithm readable while making ownership explicit in
    // `RenderEngineResources`. They are actor-isolated through their enclosing engine.
    private var context: CIContext { resources.context }
    private var device: MTLDevice? { resources.device }
    private var commandQueue: MTLCommandQueue? { resources.commandQueue }
    private var lutCache: LUTFilterCache { resources.lutCache }
    private var toneCurveCache: ToneCurveFilterCache { resources.toneCurveCache }
    private var toneCurveSource: RenderSourceFingerprint? {
        get { resources.toneCurveSource }
        set { resources.toneCurveSource = newValue }
    }
    private var toneCurveSpace: WorkingSpace? {
        get { resources.toneCurveSpace }
        set { resources.toneCurveSpace = newValue }
    }
    private var previewCache: BoundedLRUCache<PreviewCacheKey, RenderResult> { resources.previewCache }
    private var developedSourceCache: BoundedLRUCache<DevelopedSourceCacheKey, CIImage> {
        resources.developedSourceCache
    }
    private var processingPrefixCache: BoundedLRUCache<ProcessingPrefixCacheKey, CIImage> {
        resources.processingPrefixCache
    }
    /// The interactive RAW decoder is deliberately a single-entry cache. `CIRAWFilter` is mutable
    /// and is only safe behind this actor; retaining one filter for the visible source avoids
    /// rebuilding its immutable source/decode setup on every pointer tick. It is discarded at the
    /// source boundary, so a replaced URL or a different photo can never reuse decoder state.
    private var interactiveRAWSession: InteractiveRAWFilterSession?
    private var rawFilterConstructionCount = 0
    private var rawPropertyWriteCount = 0
    private var rawOutputRequestCount = 0
    private var processingPrefixMaterializationCount = 0
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(configuration: RenderCacheConfiguration = .default) {
        self.resources = RenderEngineResources(configuration: configuration)
        Task { [weak self] in await self?.installMemoryPressureMonitor() }
    }

    /// Inject a context — for tests that need to pin the backend rather than take whatever the
    /// machine offers.
    init(context: CIContext, configuration: RenderCacheConfiguration = .default) {
        self.resources = RenderEngineResources(context: context, configuration: configuration)
        Task { [weak self] in await self?.installMemoryPressureMonitor() }
    }

    // MARK: - Rendering

    /// Fast display-only rasterization. `CGImage` is created while the Core Image graph and context
    /// are still actor-local, then transferred to the UI as the one explicitly `sending` value.
    /// Keeping this accessor separate means `RenderResult` remains a small, UI-independent,
    /// Sendable value for exports and other renderer clients.
    func makeCGImage(_ request: RenderRequest) async -> sending CGImage? {
        guard request.output == .raster, !Task.isCancelled else { return nil }

        var interval = LumoObservability.begin(
            .render, source: request.source, quality: request.quality
        )
        defer { interval.end() }

        let image = buildImage(
            request.source, request.document, request.lut, request.renderScale, request.space,
            quality: request.quality
        )
        guard let image,
              image.extent.isRasterizable,
              !Task.isCancelled
        else { return nil }

        let rect = image.extent.integral
        return context.createCGImage(
            image, from: rect, format: .RGBA8, colorSpace: request.space.cgColorSpace
        )
    }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        var interval = LumoObservability.begin(
            .render, source: request.source, quality: request.quality
        )
        defer { interval.end() }

        // An interactive request can sit behind another Core Image operation on this actor. Check
        // before doing any work so cancellation drops queued superseded values instead of making
        // the coordinator wait for an obsolete graph to rasterize.
        try Task.checkCancellation()
        if let options = request.exportOptions {
            try options.validate()
            guard case .encoded(let format, _) = request.output else {
                throw ExportOptionsError.outputRequiresEncoded(expected: options.format)
            }
            guard format == options.format else {
                throw ExportOptionsError.outputFormatMismatch(expected: options.format, actual: format)
            }
        }
        let scale = request.renderScale
        let previewKey = previewCacheKey(for: request, scale: scale)
        if let previewKey {
            var cacheInterval = LumoObservability.begin(.cache, source: request.source,
                                                        quality: request.quality)
            defer { cacheInterval.end() }
            if let cached = previewCache.value(for: previewKey) {
                LumoObservability.event(.cacheHit, source: request.source, quality: request.quality,
                                        detail: "layer=preview")
                return cached
            }
            LumoObservability.event(.cacheMiss, source: request.source, quality: request.quality,
                                    detail: "layer=preview")
        }

        let image: CIImage?
        let outputSpace = request.exportOptions?.colorSpace ?? request.space
        if scale.isFull {
            var decodeInterval = LumoObservability.begin(
                .decode, source: request.source, quality: request.quality
            )
            image = buildImage(request.source, request.document, request.lut, scale, outputSpace,
                               quality: request.quality)
            decodeInterval.end()
        } else {
            image = buildImage(request.source, request.document, request.lut, scale, outputSpace,
                               quality: request.quality)
        }
        guard let image else {
            throw ImageError.processingFailed
        }
        let outputImage: CIImage
        if let exportOutputSize = request.exportOutputSize {
            outputImage = RenderPipeline.resized(image, to: exportOutputSize)
        } else {
            outputImage = image
        }
        try Task.checkCancellation()
        let rect = outputImage.extent.integral
        guard rect.isRasterizable else { throw ImageError.processingFailed }
        let colorSpace = outputSpace.cgColorSpace

        let data: Data
        switch request.output {
        case .raster:
            guard let raster = context.pngRepresentation(
                of: outputImage, format: .RGBA8, colorSpace: colorSpace
            ) else { throw ImageError.processingFailed }
            data = raster

        case .encoded(let format, let quality):
            let options = request.exportOptions
            let bitDepth = options?.bitDepth ?? format.defaultBitDepth
            let alpha = options?.alpha ?? format.defaultAlpha
            let encodedImage = alpha == .opaque ? opaqueImage(outputImage) : outputImage
            let representationFormat: CIFormat
            switch (bitDepth, alpha) {
            case (.sixteen, .preserve): representationFormat = .RGBA16
            case (.sixteen, .opaque): representationFormat = .RGBA16
            case (.eight, .preserve), (.eight, .opaque): representationFormat = .RGBA8
            }
            switch format {
            case .tiff:
                data = try encode(
                    encodedImage,
                    format: format,
                    representationFormat: representationFormat,
                    colorSpace: colorSpace,
                    quality: quality,
                    metadata: exportMetadata(for: request)
                )
            case .jpeg:
                data = try encode(
                    encodedImage,
                    format: format,
                    representationFormat: .RGBA8,
                    colorSpace: colorSpace,
                    quality: quality,
                    metadata: exportMetadata(for: request)
                )
            case .png:
                data = try encode(
                    encodedImage,
                    format: format,
                    representationFormat: representationFormat,
                    colorSpace: colorSpace,
                    quality: quality,
                    metadata: exportMetadata(for: request)
                )
            case .heif:
                data = try encode(
                    encodedImage,
                    format: format,
                    representationFormat: .RGBA8,
                    colorSpace: colorSpace,
                    quality: quality,
                    metadata: exportMetadata(for: request)
                )
            }
        }

        try Task.checkCancellation()

        let result = RenderResult(
            data: data, extent: rect.size, colorSpace: outputSpace,
            quality: request.quality, output: request.output
        )
        if let previewKey {
            previewCache.insert(result, for: previewKey, cost: data.count)
        }
        try Task.checkCancellation()
        return result
    }

    /// Flatten an opaque export against white while keeping the Core Image graph actor-local.
    private func opaqueImage(_ image: CIImage) -> CIImage {
        let background = CIImage(
            color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        ).cropped(to: image.extent)
        return image.composited(over: background)
    }

    /// Encode a completed Core Image graph through Image I/O so source metadata can be supplied to
    /// the destination. Core Image's representation helpers do not expose the source property
    /// dictionaries, while `CGImageDestinationAddImage` writes them for all three export formats.
    private func encode(
        _ image: CIImage,
        format: ExportFormat,
        representationFormat: CIFormat,
        colorSpace: CGColorSpace,
        quality: CGFloat,
        metadata: [CFString: Any]?
    ) throws -> Data {
        guard let cgImage = context.createCGImage(
            image,
            from: image.extent.integral,
            format: representationFormat,
            colorSpace: colorSpace
        ) else {
            throw ImageError.exportFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, format.utType.identifier as CFString, 1, nil
        ) else {
            throw ImageError.exportFailed
        }

        var imageProperties = metadata ?? [:]
        if format == .jpeg || format == .heif {
            imageProperties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, cgImage,
                                   imageProperties.isEmpty ? nil : imageProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageError.exportFailed
        }
        return data as Data
    }

    /// Read only the source's metadata dictionaries. The image itself is rendered upright before
    /// this is called, so copying the source orientation would apply that transform a second time.
    /// Pixel dimensions are likewise omitted: a long-edge export may intentionally resize them.
    /// GPS is independently controlled because preserving camera metadata does not imply consent
    /// to share precise location.
    private func exportMetadata(for request: RenderRequest) -> [CFString: Any]? {
        let policy = request.exportOptions?.metadata ?? .preserve
        guard policy == .preserve else { return nil }
        let locationPolicy = request.exportOptions?.location ?? .exclude

        let source: CGImageSource?
        switch request.source.backing {
        case .url(let url):
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        case .data(let data):
            source = CGImageSourceCreateWithData(data as CFData, nil)
        }
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else {
            return nil
        }

        var dictionaryKeys: [CFString] = [
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyExifDictionary,
        ]
        if locationPolicy == .include {
            dictionaryKeys.append(kCGImagePropertyGPSDictionary)
        }
        var metadata: [CFString: Any] = [:]
        for key in dictionaryKeys {
            guard var dictionary = properties[key] as? [CFString: Any], !dictionary.isEmpty else {
                continue
            }
            if key == kCGImagePropertyTIFFDictionary {
                dictionary.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            } else if key == kCGImagePropertyExifDictionary {
                dictionary.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
                dictionary.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            }
            if !dictionary.isEmpty {
                metadata[key] = dictionary
            }
        }
        return metadata.isEmpty ? nil : metadata
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
        var interval = LumoObservability.begin(.histogram, source: source, quality: .preview)
        defer { interval.end() }

        guard !Task.isCancelled,
              maxDimension > 0,
              let image = buildImage(source, document, lut, scale, space, quality: .preview) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
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
        guard !Task.isCancelled, width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard !Task.isCancelled else { return nil }
        bytes.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            guard !Task.isCancelled else { return }
            context.render(
                scaled, toBitmap: base, rowBytes: bytesPerRow, bounds: rect,
                format: .RGBA8, colorSpace: space.cgColorSpace
            )
        }
        guard !Task.isCancelled else { return nil }
        return HistogramData(rgba8: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    // MARK: - RAW capabilities

    /// Admit a source using value geometry only. Standard-image dimensions come from ImageIO;
    /// RAW dimensions come from the renderer-owned session without touching `outputImage`.
    func prepareSource(_ source: ImageSource) -> ImageSourcePreparation? {
        switch source.kind {
        case .standard:
            guard let prepared = try? standardPreparation(for: source) else { return nil }
            return prepared
        case .raw:
            guard let session = session(for: source) else { return nil }
            let preparedSource = ImageSource(
                backing: source.backing, kind: .raw, nativeExtent: session.nativeSize
            )
            return ImageSourcePreparation(source: preparedSource)
        }
    }

    private func standardPreparation(for source: ImageSource) throws -> ImageSourcePreparation {
        let extent: CGSize
        switch source.backing {
        case .url(let url):
            extent = try ImageDecoder.prepareStandard(from: url)
        case .data(let data):
            extent = try ImageDecoder.prepareStandard(from: data, name: "import")
        }
        return ImageSourcePreparation(source: ImageSource(
            backing: source.backing, kind: .standard, nativeExtent: extent
        ))
    }

    /// Read capabilities from the same renderer-owned session used for preparation and preview.
    ///
    /// **`outputImage` is deliberately never touched.** That is the difference between ~25 ms and
    /// ~183 ms on a 30 MB DNG (measured; see the Step 10a design doc), and it is why this can run on
    /// every image open without being felt. It also leaves the developed-source memo alone — a
    /// capability question must not evict the image the user is looking at.
    ///
    /// **A gated seed is read only when its gate is open.** Every property below the `is*Supported`
    /// line is a knob this particular decoder may not offer, and what an unoffered property returns is
    /// not a default the panel should show — it is nothing at all. Where the gate is shut the seed
    /// stays at `RAWCapabilities`' own default, which no control can reach anyway: `supports(_:)`
    /// withdraws the control on the same flag.
    func rawCapabilities(for source: ImageSource) -> RAWCapabilities? {
        guard case .raw = source.kind else { return nil }
        guard let session = session(for: source) else { return nil }
        let captured = session.capabilities()
        // Keep the capability-to-seed relationship explicit at this API boundary. The session has
        // already captured these values before any mutable development output can change them.
        return RAWCapabilities(
            isSharpnessSupported: captured.isSharpnessSupported,
            isContrastSupported: captured.isContrastSupported,
            isDetailSupported: captured.isDetailSupported,
            isMoireReductionSupported: captured.isMoireReductionSupported,
            isLocalToneMapSupported: captured.isLocalToneMapSupported,
            isLuminanceNoiseReductionSupported: captured.isLuminanceNoiseReductionSupported,
            isColorNoiseReductionSupported: captured.isColorNoiseReductionSupported,
            isLensCorrectionSupported: captured.isLensCorrectionSupported,
            isHighlightRecoverySupported: captured.isHighlightRecoverySupported,
            asShotTemperature: captured.asShotTemperature,
            asShotTint: captured.asShotTint,
            baselineExposure: captured.baselineExposure,
            shadowBias: captured.shadowBias,
            sharpnessAmount: captured.isSharpnessSupported ? captured.sharpnessAmount : 0,
            contrastAmount: captured.isContrastSupported ? captured.contrastAmount : 0,
            detailAmount: captured.isDetailSupported ? captured.detailAmount : 0,
            moireReductionAmount:
                captured.isMoireReductionSupported ? captured.moireReductionAmount : 0,
            localToneMapAmount:
                captured.isLocalToneMapSupported ? captured.localToneMapAmount : 0,
            luminanceNoiseReductionAmount: captured.isLuminanceNoiseReductionSupported
                ? captured.luminanceNoiseReductionAmount : 0,
            colorNoiseReductionAmount: captured.isColorNoiseReductionSupported
                ? captured.colorNoiseReductionAmount : 0,
            lensCorrectionEnabled:
                captured.isLensCorrectionSupported ? captured.lensCorrectionEnabled : false
        )
    }

    private func session(for source: ImageSource) -> InteractiveRAWFilterSession? {
        let fingerprint = source.decoderFingerprint
        if interactiveRAWSession?.fingerprint != fingerprint {
            // This is the one renderer-owned RAW session. Replacing it releases the old source
            // graph before the new source is admitted, keeping rapid navigation bounded.
            interactiveRAWSession = InteractiveRAWFilterSession(source: source)
            if interactiveRAWSession != nil { rawFilterConstructionCount += 1 }
        }
        return interactiveRAWSession
    }

    // MARK: - Cache

    /// Drop every cached LUT-dependent render resource. For a library rescan: a `LUTID` is a file
    /// path, so a `.cube` edited in place keeps its ID and would otherwise keep serving the old cube.
    func invalidateLUTCache() {
        // A preview submitted while a scan was unresolved has no LUT fingerprint. Clear it too so
        // the scan completion can safely publish a newly resolved render.
        resources.invalidateLUTDependentCaches()
    }

    /// Snapshot cache counters for instrumentation and performance diagnostics.
    func cacheStatistics() -> RenderCacheStatistics {
        RenderCacheStatistics(
            preview: previewCache.statistics,
            developedSource: developedSourceCache.statistics,
            processingPrefix: processingPrefixCache.statistics,
            lutFilter: lutCache.statistics
        )
    }

    func workStatistics() -> RenderWorkStatistics {
        RenderWorkStatistics(
            rawFilterConstructions: rawFilterConstructionCount,
            rawPropertyWrites: rawPropertyWriteCount,
            rawOutputRequests: rawOutputRequestCount,
            processingPrefixMaterializations: processingPrefixMaterializationCount
        )
    }

    /// Release all reusable intermediates. This is also the memory-pressure handler.
    func evictForMemoryPressure() {
        resources.evictAll()
        interactiveRAWSession = nil
        Thumbnails.evictForMemoryPressure()
    }

    /// Explicit invalidation for a source-folder refresh or a caller that knows a source changed.
    func invalidateRenderCaches() {
        resources.invalidateAll()
        interactiveRAWSession = nil
        Thumbnails.invalidateCache()
    }

    /// How many cube filters are held. Internal for the tests that prove the cache is actually being
    /// used across renders rather than rebuilt each time — there is no other way to observe it from
    /// outside, and a silently-bypassed cache is invisible in the output.
    var cachedFilterCount: Int { lutCache.count }

    // MARK: - Private

    /// Allocate the completed-frame surface. The image stays texture-backed all the way to the
    /// main-actor presentation pass; there is intentionally no PNG/CGImage/CPU readback seam here.
    private func makePreviewTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = width
        descriptor.height = height
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    /// Turn the processing command buffer into the renderer's pacing boundary without blocking
    /// the actor thread. The handler is installed before commit; otherwise Metal rejects a late
    /// handler on a command buffer that has already been submitted. Cancellation is checked by the
    /// caller after this continuation resumes, so the GPU resource is never handed to presentation
    /// while its write is still in flight.
    private func commitAndWaitForCompletion(_ commandBuffer: MTLCommandBuffer) async -> Bool {
        await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { buffer in
                continuation.resume(returning: buffer.status == .completed)
            }
            commandBuffer.commit()
        }
    }

    /// One funnel, so preview and export cannot diverge in how they build the graph — only in the
    /// scale they ask for.
    private func buildImage(
        _ source: ImageSource,
        _ document: EditDocument,
        _ lut: CubeLUT?,
        _ scale: RenderScale,
        _ space: WorkingSpace,
        quality: RenderQuality
    ) -> CIImage? {
        // These are explicit Core Image resource boundaries even though the transfer function is
        // mathematically source/space independent. A replaced source or working-space switch must
        // not retain a resource from the prior render session.
        let sourceFingerprint = RenderSourceFingerprint(source)
        if toneCurveSource != sourceFingerprint || toneCurveSpace != space {
            toneCurveCache.removeAll()
            toneCurveSource = sourceFingerprint
            toneCurveSpace = space
        }
        guard let developed = developedSource(
            source, document.rawDevelop, scale, space: space,
            interactive: quality == .interactive
        ) else { return nil }
        let includePostRenderWhiteBalance = source.kind == .standard
        let upstream: CIImage
        if !scale.isFull, RenderPipeline.hasPreLUTWork(
            document, includePostRenderWhiteBalance: includePostRenderWhiteBalance
        ) {
            upstream = processingPrefix(
                source: source, document: document, developed: developed, scale: scale,
                space: space, includePostRenderWhiteBalance: includePostRenderWhiteBalance,
                quality: quality
            ) ?? RenderPipeline.buildPreLUTImage(
                developed: developed, document: document, toneCurveCache: toneCurveCache,
                includePostRenderWhiteBalance: includePostRenderWhiteBalance
            )
        } else {
            upstream = RenderPipeline.buildPreLUTImage(
                developed: developed, document: document, toneCurveCache: toneCurveCache,
                includePostRenderWhiteBalance: includePostRenderWhiteBalance
            )
        }
        return RenderStageFacade.buildFinalStages(
            preLUT: upstream, document: document, lut: lut, space: space, lutCache: lutCache,
            grainSeed: RenderPipeline.grainSeed(for: source)
        )
    }

    private struct MaterializedImage {
        let image: CIImage
        let costBytes: Int
    }

    /// Complete a prefix at half-float precision so later graph construction cannot pull the RAW
    /// decoder or expensive spatial nodes back into the next LUT/grain evaluation. This is a
    /// bounded, preview-only boundary; full-resolution/export requests stay on the original fused
    /// graph and never pay for an intermediate readback.
    private func materializedImage(_ image: CIImage, space: WorkingSpace) -> MaterializedImage? {
        let rect = image.extent.integral
        guard rect.isRasterizable,
              rect.width <= CGFloat(Int.max), rect.height <= CGFloat(Int.max),
              rect.width > 0, rect.height > 0 else { return nil }
        let width = Int(rect.width)
        let height = Int(rect.height)
        let rowBytes = width.multipliedReportingOverflow(by: 8)
        guard !rowBytes.overflow else { return nil }
        let byteCount = rowBytes.partialValue.multipliedReportingOverflow(by: height)
        guard !byteCount.overflow else { return nil }

        var data = Data(repeating: 0, count: byteCount.partialValue)
        data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            context.render(
                image, toBitmap: baseAddress, rowBytes: rowBytes.partialValue, bounds: rect,
                format: .RGBAh, colorSpace: space.cgColorSpace
            )
        }
        let image = CIImage(
            bitmapData: data, bytesPerRow: rowBytes.partialValue, size: rect.size,
            format: .RGBAh, colorSpace: space.cgColorSpace
        )
        let positioned = rect.origin == .zero
            ? image
            : image.transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return MaterializedImage(image: positioned, costBytes: byteCount.partialValue)
    }

    private func processingPrefix(
        source: ImageSource,
        document: EditDocument,
        developed: CIImage,
        scale: RenderScale,
        space: WorkingSpace,
        includePostRenderWhiteBalance: Bool,
        quality: RenderQuality
    ) -> CIImage? {
        let key = ProcessingPrefixCacheKey(
            source: RenderSourceFingerprint(source),
            developHash: RenderCacheHash.digest(document.rawDevelop),
            upstreamHash: prefixDocumentHash(
                document, includePostRenderWhiteBalance: includePostRenderWhiteBalance
            ),
            scale: RenderScaleKey(scale, nativeExtent: source.nativeExtent),
            space: space,
            includePostRenderWhiteBalance: includePostRenderWhiteBalance,
            pipelineVersion: RenderPipeline.cacheVersion
        )
        if let cached = processingPrefixCache.value(for: key) {
            LumoObservability.event(.cacheHit, source: source, quality: quality,
                                    detail: "layer=processingPrefix")
            return cached
        }
        LumoObservability.event(.cacheMiss, source: source, quality: quality,
                                detail: "layer=processingPrefix")

        let prefix = RenderPipeline.buildPreLUTImage(
            developed: developed, document: document, toneCurveCache: toneCurveCache,
            includePostRenderWhiteBalance: includePostRenderWhiteBalance
        )
        guard let completed = materializedImage(prefix, space: space) else { return nil }
        processingPrefixMaterializationCount += 1
        processingPrefixCache.insert(completed.image, for: key, cost: completed.costBytes)
        return completed.image
    }

    private func prefixDocumentHash(
        _ document: EditDocument,
        includePostRenderWhiteBalance: Bool
    ) -> String {
        let adjustments = includePostRenderWhiteBalance
            ? document.adjustments
            : document.adjustments.filter {
                if case .temperatureTint = $0 { return false }
                return true
            }
        return RenderCacheHash.digest(EditDocument(
            version: document.version, rawDevelop: .neutral, light: document.light,
            color: document.color,
            effects: EffectsAdjustments(
                texture: document.effects.texture, clarity: document.effects.clarity,
                dehaze: document.effects.dehaze
            ), crop: .neutral, adjustments: adjustments, lut: .none
        ))
    }

    // MARK: - The developed-source cache

    /// The source stage, cached for **preview** renders.
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
    /// Several entries are retained so stepping back through a folder can hit, but both a count and
    /// an estimated decoded-byte limit keep a long navigation session bounded.
    private func developedSource(
        _ source: ImageSource,
        _ rawDevelop: RAWDevelopSettings,
        _ scale: RenderScale,
        space: WorkingSpace,
        interactive: Bool = false
    ) -> CIImage? {
        let canUsePreparedSession = source.kind == .raw && !scale.isFull &&
            (interactive || interactiveRAWSession?.fingerprint == source.decoderFingerprint)
        if canUsePreparedSession {
            let fingerprint = source.decoderFingerprint
            let reused = interactiveRAWSession?.fingerprint == fingerprint
            guard let session = session(for: source) else { return nil }
            LumoObservability.event(
                reused ? .cacheHit : .cacheMiss, source: source, quality: .interactive,
                detail: "layer=interactiveRAWFilter reused=\(reused)"
            )
            let result = session.output(
                rawDevelop: rawDevelop, scale: scale,
                materialize: { [self] image in materializedImage(image, space: space)?.image }
            )
            rawPropertyWriteCount += result.propertyWrites
            if result.requestedOutput { rawOutputRequestCount += 1 }
            return result.image
        }
        guard !scale.isFull else {
            return RenderPipeline.developedSource(source, rawDevelop: rawDevelop, scale: scale)
        }
        let key = DevelopedSourceCacheKey(
            source: RenderSourceFingerprint(source),
            developHash: RenderCacheHash.digest(rawDevelop),
            scale: RenderScaleKey(scale, nativeExtent: source.nativeExtent),
            pipelineVersion: RenderPipeline.cacheVersion
        )
        var cacheInterval = LumoObservability.begin(.cache, source: source, quality: .preview)
        let cachedImage = developedSourceCache.value(for: key)
        cacheInterval.end()
        if let image = cachedImage {
            LumoObservability.event(.cacheHit, source: source, quality: .preview,
                                    detail: "layer=developedSource")
            return image
        }

        LumoObservability.event(.cacheMiss, source: source, quality: .preview,
                                detail: "layer=developedSource")

        var decodeInterval = LumoObservability.begin(.decode, source: source, quality: .preview)
        defer { decodeInterval.end() }

        guard let image = RenderPipeline.developedSource(
            source, rawDevelop: rawDevelop, scale: scale
        ) else { return nil }

        // RAW output is mutable-filter-backed. Complete it before putting it in the settled cache,
        // otherwise a later render can ask Core Image to evaluate the same decoder graph again.
        if source.kind == .raw, let completed = materializedImage(image, space: space) {
            developedSourceCache.insert(completed.image, for: key, cost: completed.costBytes)
            return completed.image
        }

        let extent = image.extent.integral
        let byteCount = estimatedByteCost(extent: extent, bytesPerPixel: 4)
        developedSourceCache.insert(image, for: key, cost: byteCount)
        return image
    }

    private func estimatedByteCost(extent: CGRect, bytesPerPixel: Int) -> Int {
        guard extent.width > 0, extent.height > 0,
              extent.width <= CGFloat(Int.max), extent.height <= CGFloat(Int.max) else {
            return Int.max
        }
        let width = Int(extent.width)
        let height = Int(extent.height)
        let row = width.multipliedReportingOverflow(by: max(0, bytesPerPixel))
        guard !row.overflow else { return Int.max }
        let total = row.partialValue.multipliedReportingOverflow(by: height)
        return total.overflow ? Int.max : total.partialValue
    }

    /// Drop the developed-source memo. Not needed for correctness — the key covers every input — but
    /// it lets a caller release the intermediates when no image is on screen.
    func invalidateSourceCache() {
        developedSourceCache.removeAll()
        processingPrefixCache.removeAll()
        interactiveRAWSession = nil
        toneCurveCache.removeAll()
        toneCurveSource = nil
        toneCurveSpace = nil
    }

    /// A reusable actor-local RAW filter for the short-lived interactive tier. The baseline values
    /// are captured once because applying an optional setting cannot undo a value written on the
    /// previous tick (`nil` means decoder default, not "clear this mutable filter property").
    private final class InteractiveRAWFilterSession {
        struct OutputResult {
            let image: CIImage?
            let propertyWrites: Int
            let requestedOutput: Bool
        }

        private struct OutputKey: Equatable {
            let sourceRevision: String
            let developHash: String
            let scale: RenderScaleKey
        }

        let fingerprint: String
        private let filter: CIRAWFilter
        private let baseline: RAWFilterBaseline
        private let capturedCapabilities: RAWCapabilities
        private var appliedSettings: RAWDevelopSettings?
        private var appliedScaleFactor: Float?
        private var cachedOutputKey: OutputKey?
        private var cachedOutput: CIImage?

        var nativeSize: CGSize { filter.nativeSize }

        init?(source: ImageSource) {
            guard let filter = RenderPipeline.rawFilter(for: source.backing) else { return nil }
            self.fingerprint = source.decoderFingerprint
            self.filter = filter
            self.baseline = RAWFilterBaseline(filter: filter)
            self.capturedCapabilities = Self.captureCapabilities(filter)
        }

        func capabilities() -> RAWCapabilities {
            capturedCapabilities
        }

        private static func captureCapabilities(_ filter: CIRAWFilter) -> RAWCapabilities {
            var highlightRecovery = false
            if #available(macOS 26, *) {
                highlightRecovery = filter.isHighlightRecoverySupported
            }
            return RAWCapabilities(
                isSharpnessSupported: filter.isSharpnessSupported,
                isContrastSupported: filter.isContrastSupported,
                isDetailSupported: filter.isDetailSupported,
                isMoireReductionSupported: filter.isMoireReductionSupported,
                isLocalToneMapSupported: filter.isLocalToneMapSupported,
                isLuminanceNoiseReductionSupported: filter.isLuminanceNoiseReductionSupported,
                isColorNoiseReductionSupported: filter.isColorNoiseReductionSupported,
                isLensCorrectionSupported: filter.isLensCorrectionSupported,
                isHighlightRecoverySupported: highlightRecovery,
                asShotTemperature: Double(filter.neutralTemperature),
                asShotTint: Double(filter.neutralTint),
                baselineExposure: Double(filter.baselineExposure),
                shadowBias: Double(filter.shadowBias),
                sharpnessAmount: filter.isSharpnessSupported ? Double(filter.sharpnessAmount) : 0,
                contrastAmount: filter.isContrastSupported ? Double(filter.contrastAmount) : 0,
                detailAmount: filter.isDetailSupported ? Double(filter.detailAmount) : 0,
                moireReductionAmount:
                    filter.isMoireReductionSupported ? Double(filter.moireReductionAmount) : 0,
                localToneMapAmount:
                    filter.isLocalToneMapSupported ? Double(filter.localToneMapAmount) : 0,
                luminanceNoiseReductionAmount: filter.isLuminanceNoiseReductionSupported
                    ? Double(filter.luminanceNoiseReductionAmount) : 0,
                colorNoiseReductionAmount: filter.isColorNoiseReductionSupported
                    ? Double(filter.colorNoiseReductionAmount) : 0,
                lensCorrectionEnabled:
                    filter.isLensCorrectionSupported ? filter.isLensCorrectionEnabled : false
            )
        }

        func output(
            rawDevelop: RAWDevelopSettings,
            scale: RenderScale,
            materialize: (CIImage) -> CIImage?
        ) -> OutputResult {
            let factor = scale.factor(for: filter.nativeSize)
            let key = OutputKey(
                sourceRevision: fingerprint,
                developHash: RenderCacheHash.digest(rawDevelop),
                scale: RenderScaleKey(scale, nativeExtent: filter.nativeSize)
            )
            if cachedOutputKey == key, let cachedOutput {
                return OutputResult(image: cachedOutput, propertyWrites: 0, requestedOutput: false)
            }

            let propertyWrites = baseline.apply(
                changedFrom: appliedSettings, to: rawDevelop, filter: filter
            )
            appliedSettings = rawDevelop
            let scaleFactor = Float(factor)
            if appliedScaleFactor != scaleFactor {
                filter.scaleFactor = scaleFactor
                appliedScaleFactor = scaleFactor
            }
            guard let output = filter.outputImage else {
                return OutputResult(image: nil, propertyWrites: propertyWrites, requestedOutput: true)
            }
            guard let completed = materialize(output) else {
                // The mutable filter remains correctly configured, but do not retain its lazy
                // output: a later property write could otherwise change the image behind the cache.
                cachedOutputKey = nil
                cachedOutput = nil
                return OutputResult(image: output, propertyWrites: propertyWrites, requestedOutput: true)
            }
            cachedOutputKey = key
            cachedOutput = completed
            return OutputResult(image: completed, propertyWrites: propertyWrites, requestedOutput: true)
        }
    }

    /// All mutable develop values touched by `RAWDevelopSettings.apply`. Keeping this snapshot
    /// local to the renderer makes reset semantics explicit without sharing a `CIRAWFilter` across
    /// actors or changing the settled, deterministic pipeline.
    private struct RAWFilterBaseline {
        let exposure: Float
        let baselineExposure: Float
        let shadowBias: Float
        let boostAmount: Float
        let boostShadowAmount: Float
        let neutralTemperature: Float
        let neutralTint: Float
        let gamutMappingEnabled: Bool
        let extendedDynamicRangeAmount: Float
        let sharpnessAmount: Float
        let contrastAmount: Float
        let detailAmount: Float
        let moireReductionAmount: Float
        let localToneMapAmount: Float
        let luminanceNoiseReductionAmount: Float
        let colorNoiseReductionAmount: Float
        let lensCorrectionEnabled: Bool
        let highlightRecoveryEnabled: Bool?

        init(filter: CIRAWFilter) {
            exposure = filter.exposure; baselineExposure = filter.baselineExposure
            shadowBias = filter.shadowBias; boostAmount = filter.boostAmount
            boostShadowAmount = filter.boostShadowAmount
            neutralTemperature = filter.neutralTemperature; neutralTint = filter.neutralTint
            gamutMappingEnabled = filter.isGamutMappingEnabled
            extendedDynamicRangeAmount = filter.extendedDynamicRangeAmount
            sharpnessAmount = filter.sharpnessAmount; contrastAmount = filter.contrastAmount
            detailAmount = filter.detailAmount; moireReductionAmount = filter.moireReductionAmount
            localToneMapAmount = filter.localToneMapAmount
            luminanceNoiseReductionAmount = filter.luminanceNoiseReductionAmount
            colorNoiseReductionAmount = filter.colorNoiseReductionAmount
            lensCorrectionEnabled = filter.isLensCorrectionEnabled
            if #available(macOS 26, *), filter.isHighlightRecoverySupported {
                highlightRecoveryEnabled = filter.isHighlightRecoveryEnabled
            } else { highlightRecoveryEnabled = nil }
        }

        func apply(
            changedFrom previous: RAWDevelopSettings?,
            to next: RAWDevelopSettings,
            filter: CIRAWFilter
        ) -> Int {
            var writeCount = 0
            if previous?.exposure != next.exposure {
                writeCount += 1
                filter.exposure = next.exposure.map(Float.init) ?? exposure
            }
            if previous?.baselineExposure != next.baselineExposure {
                writeCount += 1
                filter.baselineExposure = next.baselineExposure.map(Float.init) ?? baselineExposure
            }
            if previous?.shadowBias != next.shadowBias {
                writeCount += 1
                filter.shadowBias = next.shadowBias.map(Float.init) ?? shadowBias
            }
            if previous?.boostAmount != next.boostAmount {
                writeCount += 1
                filter.boostAmount = next.boostAmount.map(Float.init) ?? boostAmount
            }
            if previous?.boostShadowAmount != next.boostShadowAmount {
                writeCount += 1
                filter.boostShadowAmount = next.boostShadowAmount.map(Float.init) ?? boostShadowAmount
            }
            if previous?.neutralTemperature != next.neutralTemperature {
                writeCount += 1
                filter.neutralTemperature = next.neutralTemperature.map(Float.init) ?? neutralTemperature
            }
            if previous?.neutralTint != next.neutralTint {
                writeCount += 1
                filter.neutralTint = next.neutralTint.map(Float.init) ?? neutralTint
            }
            if previous?.gamutMappingEnabled != next.gamutMappingEnabled {
                writeCount += 1
                filter.isGamutMappingEnabled = next.gamutMappingEnabled ?? gamutMappingEnabled
            }
            if previous?.extendedDynamicRangeAmount != next.extendedDynamicRangeAmount {
                writeCount += 1
                filter.extendedDynamicRangeAmount =
                    next.extendedDynamicRangeAmount.map(Float.init) ?? extendedDynamicRangeAmount
            }
            if filter.isSharpnessSupported, previous?.sharpnessAmount != next.sharpnessAmount {
                writeCount += 1
                filter.sharpnessAmount = next.sharpnessAmount.map(Float.init) ?? sharpnessAmount
            }
            if filter.isContrastSupported, previous?.contrastAmount != next.contrastAmount {
                writeCount += 1
                filter.contrastAmount = next.contrastAmount.map(Float.init) ?? contrastAmount
            }
            if filter.isDetailSupported, previous?.detailAmount != next.detailAmount {
                writeCount += 1
                filter.detailAmount = next.detailAmount.map(Float.init) ?? detailAmount
            }
            if filter.isMoireReductionSupported, previous?.moireReductionAmount != next.moireReductionAmount {
                writeCount += 1
                filter.moireReductionAmount = next.moireReductionAmount.map(Float.init) ?? moireReductionAmount
            }
            if filter.isLocalToneMapSupported, previous?.localToneMapAmount != next.localToneMapAmount {
                writeCount += 1
                filter.localToneMapAmount = next.localToneMapAmount.map(Float.init) ?? localToneMapAmount
            }
            if filter.isLuminanceNoiseReductionSupported,
               previous?.luminanceNoiseReductionAmount != next.luminanceNoiseReductionAmount {
                writeCount += 1
                filter.luminanceNoiseReductionAmount =
                    next.luminanceNoiseReductionAmount.map(Float.init) ?? luminanceNoiseReductionAmount
            }
            if filter.isColorNoiseReductionSupported,
               previous?.colorNoiseReductionAmount != next.colorNoiseReductionAmount {
                writeCount += 1
                filter.colorNoiseReductionAmount =
                    next.colorNoiseReductionAmount.map(Float.init) ?? colorNoiseReductionAmount
            }
            if filter.isLensCorrectionSupported,
               previous?.lensCorrectionEnabled != next.lensCorrectionEnabled {
                writeCount += 1
                filter.isLensCorrectionEnabled = next.lensCorrectionEnabled ?? lensCorrectionEnabled
            }
            if previous?.highlightRecoveryEnabled != next.highlightRecoveryEnabled,
               let baseline = highlightRecoveryEnabled,
               #available(macOS 26, *), filter.isHighlightRecoverySupported {
                writeCount += 1
                filter.isHighlightRecoveryEnabled = next.highlightRecoveryEnabled ?? baseline
            }
            return writeCount
        }
    }

    private func previewCacheKey(for request: RenderRequest, scale: RenderScale) -> PreviewCacheKey? {
        guard !scale.isFull, request.output == .raster else { return nil }
        guard request.quality == .thumbnail || request.quality == .interactive || request.quality == .preview else {
            return nil
        }
        return PreviewCacheKey(
            source: RenderSourceFingerprint(request.source),
            documentHash: RenderCacheHash.digest(request.document),
            lutFingerprint: request.lut?.cacheFingerprint ?? "none",
            targetScale: RenderScaleKey(scale, nativeExtent: request.source.nativeExtent),
            quality: request.quality,
            space: request.space,
            pipelineVersion: RenderPipeline.cacheVersion
        )
    }

    private func installMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler(handler: { [weak self] in
            Task { await self?.evictForMemoryPressure() }
        })
        source.resume()
        memoryPressureSource = source
    }
}
