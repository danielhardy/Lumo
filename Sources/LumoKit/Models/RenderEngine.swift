import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import Metal

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

extension RenderEngining {
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

    private let context: CIContext
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?

    /// Cube filters, reused across renders. Lives here rather than on `CubeLUT` because it is mutable
    /// reference state: a `CIFilter` gets its `inputImage` written on every use, so it is only safe
    /// behind this actor's serialization (§4.5).
    private let lutCache = LUTFilterCache()
    /// One-entry, small-resource cache for the master curve. It is actor-confined just like the
    /// LUT cache; changing the curve replaces a 4 KiB texture and never allocates a 64³ cube.
    private let toneCurveCache = ToneCurveFilterCache()
    private var toneCurveSource: RenderSourceFingerprint?
    private var toneCurveSpace: WorkingSpace?
    private let previewCache: BoundedLRUCache<PreviewCacheKey, RenderResult>
    private let developedSourceCache: BoundedLRUCache<DevelopedSourceCacheKey, CIImage>
    /// The interactive RAW decoder is deliberately a single-entry cache. `CIRAWFilter` is mutable
    /// and is only safe behind this actor; retaining one filter for the visible source avoids
    /// rebuilding its immutable source/decode setup on every pointer tick. It is discarded at the
    /// source boundary, so a replaced URL or a different photo can never reuse decoder state.
    private var interactiveRAWSession: InteractiveRAWFilterSession?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(configuration: RenderCacheConfiguration = .default) {
        // The processing context owns its queue. Using contextWithMTLCommandQueue makes the
        // asynchronous completion boundary explicit instead of letting Core Image hide work in an
        // internal queue that the caller cannot pace.
        if let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() {
            self.device = device
            self.commandQueue = queue
            self.context = CIContext(mtlCommandQueue: queue)
        } else {
            self.device = nil
            self.commandQueue = nil
            self.context = CIContext()
        }
        self.previewCache = BoundedLRUCache(
            maxEntries: configuration.previewMaxEntries,
            maxCostBytes: configuration.previewMaxCostBytes
        )
        self.developedSourceCache = BoundedLRUCache(
            maxEntries: configuration.developedSourceMaxEntries,
            maxCostBytes: configuration.developedSourceMaxCostBytes
        )
        Task { [weak self] in await self?.installMemoryPressureMonitor() }
    }

    /// Inject a context — for tests that need to pin the backend rather than take whatever the
    /// machine offers.
    init(context: CIContext, configuration: RenderCacheConfiguration = .default) {
        self.context = context
        // An injected context may be CPU-backed or may target a device unknown to the caller, so
        // retain the deterministic graph seam for tests instead of guessing a mismatched device.
        self.device = nil
        self.commandQueue = nil
        self.previewCache = BoundedLRUCache(
            maxEntries: configuration.previewMaxEntries,
            maxCostBytes: configuration.previewMaxCostBytes
        )
        self.developedSourceCache = BoundedLRUCache(
            maxEntries: configuration.developedSourceMaxEntries,
            maxCostBytes: configuration.developedSourceMaxCostBytes
        )
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
        if scale.isFull {
            var decodeInterval = LumoObservability.begin(
                .decode, source: request.source, quality: request.quality
            )
            image = buildImage(request.source, request.document, request.lut, scale, request.space,
                               quality: request.quality)
            decodeInterval.end()
        } else {
            image = buildImage(request.source, request.document, request.lut, scale, request.space,
                               quality: request.quality)
        }
        guard let image else {
            throw ImageError.processingFailed
        }
        let rect = image.extent.integral
        guard rect.isRasterizable else { throw ImageError.processingFailed }
        let colorSpace = request.space.cgColorSpace

        let data: Data
        switch request.output {
        case .raster:
            guard let raster = context.pngRepresentation(
                of: image, format: .RGBA8, colorSpace: colorSpace
            ) else { throw ImageError.processingFailed }
            data = raster

        case .encoded(let format, let quality):
            switch format {
            case .tiff:
                guard let encoded = context.tiffRepresentation(
                    of: image, format: .RGBA16, colorSpace: colorSpace
                ) else { throw ImageError.exportFailed }
                data = encoded
            case .jpeg:
                guard let encoded = context.jpegRepresentation(
                    of: image, colorSpace: colorSpace,
                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
                ) else { throw ImageError.exportFailed }
                data = encoded
            case .png:
                guard let encoded = context.pngRepresentation(
                    of: image, format: .RGBA8, colorSpace: colorSpace
                ) else { throw ImageError.exportFailed }
                data = encoded
            }
        }

        let result = RenderResult(
            data: data, extent: rect.size, colorSpace: request.space,
            quality: request.quality, output: request.output
        )
        if let previewKey {
            previewCache.insert(result, for: previewKey, cost: data.count)
        }
        try Task.checkCancellation()
        return result
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

        guard maxDimension > 0,
              let image = buildImage(source, document, lut, scale, space, quality: .preview) else {
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

    // MARK: - RAW capabilities

    /// Build a throwaway `CIRAWFilter` and read its flags and its own defaults.
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
        guard let filter = RenderPipeline.rawFilter(for: source.backing) else { return nil }

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

    // MARK: - Cache

    /// Drop every cached LUT-dependent render resource. For a library rescan: a `LUTID` is a file
    /// path, so a `.cube` edited in place keeps its ID and would otherwise keep serving the old cube.
    func invalidateLUTCache() {
        lutCache.removeAll()
        // A preview submitted while a scan was unresolved has no LUT fingerprint. Clear it too so
        // the scan completion can safely publish a newly resolved render.
        previewCache.removeAll()
    }

    /// Snapshot cache counters for instrumentation and performance diagnostics.
    func cacheStatistics() -> RenderCacheStatistics {
        RenderCacheStatistics(
            preview: previewCache.statistics,
            developedSource: developedSourceCache.statistics,
            lutFilter: lutCache.statistics
        )
    }

    /// Release all reusable intermediates. This is also the memory-pressure handler.
    func evictForMemoryPressure() {
        previewCache.removeAll(countAsEvictions: true)
        developedSourceCache.removeAll(countAsEvictions: true)
        interactiveRAWSession = nil
        lutCache.removeAll()
        toneCurveCache.removeAll()
        toneCurveSource = nil
        toneCurveSpace = nil
        Thumbnails.evictForMemoryPressure()
    }

    /// Explicit invalidation for a source-folder refresh or a caller that knows a source changed.
    func invalidateRenderCaches() {
        previewCache.removeAll()
        developedSourceCache.removeAll()
        toneCurveCache.removeAll()
        toneCurveSource = nil
        toneCurveSpace = nil
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
            source, document.rawDevelop, scale,
            interactive: quality == .interactive
        ) else { return nil }
        return RenderPipeline.buildImage(
            developed: developed, document: document, lut: lut, space: space, lutCache: lutCache,
            toneCurveCache: toneCurveCache,
            includePostRenderWhiteBalance: source.kind == .standard,
            grainSeed: RenderPipeline.grainSeed(for: source)
        )
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
        interactive: Bool = false
    ) -> CIImage? {
        if interactive, source.kind == .raw {
            let fingerprint = source.cacheFingerprint
            let reused = interactiveRAWSession?.fingerprint == fingerprint
            if interactiveRAWSession?.fingerprint != fingerprint {
                // This is an explicit one-entry boundary: source changes release the old mutable
                // Core Image object and its source-backed decode graph before creating another.
                interactiveRAWSession = InteractiveRAWFilterSession(source: source)
            }
            LumoObservability.event(
                reused ? .cacheHit : .cacheMiss, source: source, quality: .interactive,
                detail: "layer=interactiveRAWFilter reused=\(reused)"
            )
            return interactiveRAWSession?.output(rawDevelop: rawDevelop, scale: scale)
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

        let extent = image.extent.integral
        let width = max(0, Int(min(extent.width, CGFloat(Int.max))))
        let height = max(0, Int(min(extent.height, CGFloat(Int.max))))
        let pixelCount = width.multipliedReportingOverflow(by: height)
        let byteCount = pixelCount.overflow
            ? Int.max
            : pixelCount.partialValue.multipliedReportingOverflow(by: 4).partialValue
        developedSourceCache.insert(image, for: key, cost: byteCount)
        return image
    }

    /// Drop the developed-source memo. Not needed for correctness — the key covers every input — but
    /// it lets a caller release the intermediates when no image is on screen.
    func invalidateSourceCache() {
        developedSourceCache.removeAll()
        interactiveRAWSession = nil
        toneCurveCache.removeAll()
        toneCurveSource = nil
        toneCurveSpace = nil
    }

    /// A reusable actor-local RAW filter for the short-lived interactive tier. The baseline values
    /// are captured once because applying an optional setting cannot undo a value written on the
    /// previous tick (`nil` means decoder default, not "clear this mutable filter property").
    private final class InteractiveRAWFilterSession {
        let fingerprint: String
        private let filter: CIRAWFilter
        private let baseline: RAWFilterBaseline

        init?(source: ImageSource) {
            guard let filter = RenderPipeline.rawFilter(for: source.backing) else { return nil }
            self.fingerprint = source.cacheFingerprint
            self.filter = filter
            self.baseline = RAWFilterBaseline(filter: filter)
        }

        func output(rawDevelop: RAWDevelopSettings, scale: RenderScale) -> CIImage? {
            baseline.restore(to: filter)
            rawDevelop.apply(to: filter)
            let factor = scale.factor(for: filter.nativeSize)
            filter.scaleFactor = Float(factor)
            return filter.outputImage
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

        func restore(to filter: CIRAWFilter) {
            filter.exposure = exposure; filter.baselineExposure = baselineExposure
            filter.shadowBias = shadowBias; filter.boostAmount = boostAmount
            filter.boostShadowAmount = boostShadowAmount
            filter.neutralTemperature = neutralTemperature; filter.neutralTint = neutralTint
            filter.isGamutMappingEnabled = gamutMappingEnabled
            filter.extendedDynamicRangeAmount = extendedDynamicRangeAmount
            if filter.isSharpnessSupported { filter.sharpnessAmount = sharpnessAmount }
            if filter.isContrastSupported { filter.contrastAmount = contrastAmount }
            if filter.isDetailSupported { filter.detailAmount = detailAmount }
            if filter.isMoireReductionSupported { filter.moireReductionAmount = moireReductionAmount }
            if filter.isLocalToneMapSupported { filter.localToneMapAmount = localToneMapAmount }
            if filter.isLuminanceNoiseReductionSupported {
                filter.luminanceNoiseReductionAmount = luminanceNoiseReductionAmount
            }
            if filter.isColorNoiseReductionSupported {
                filter.colorNoiseReductionAmount = colorNoiseReductionAmount
            }
            if filter.isLensCorrectionSupported { filter.isLensCorrectionEnabled = lensCorrectionEnabled }
            if let highlightRecoveryEnabled, #available(macOS 26, *),
               filter.isHighlightRecoverySupported {
                filter.isHighlightRecoveryEnabled = highlightRecoveryEnabled
            }
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
