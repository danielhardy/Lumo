import CoreImage
import Metal

/// Actor-confined GPU and cache resources used by `RenderEngine`.
///
/// This is intentionally a small storage object rather than another renderer. It centralizes
/// construction and lifetime of the mutable Core Image/Metal resources while `RenderPipeline`
/// remains the pure stage builder and `RenderEngine` remains the request façade. The class is never
/// sent out of the engine actor; its non-Sendable members therefore stay behind the same isolation
/// boundary as before.
final class RenderEngineResources {
    let configuration: RenderCacheConfiguration
    let context: CIContext
    let device: MTLDevice?
    let commandQueue: MTLCommandQueue?
    let lutCache = LUTFilterCache()
    let toneCurveCache = ToneCurveFilterCache()
    var toneCurveSource: RenderSourceFingerprint?
    var toneCurveSpace: WorkingSpace?
    let previewCache: BoundedLRUCache<PreviewCacheKey, RenderResult>
    let developedSourceCache: BoundedLRUCache<DevelopedSourceCacheKey, CIImage>
    let processingPrefixCache: BoundedLRUCache<ProcessingPrefixCacheKey, CIImage>

    init(configuration: RenderCacheConfiguration) {
        self.configuration = configuration
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
        self.processingPrefixCache = BoundedLRUCache(
            maxEntries: configuration.processingPrefixMaxEntries,
            maxCostBytes: configuration.processingPrefixMaxCostBytes
        )
    }

    init(context: CIContext, configuration: RenderCacheConfiguration) {
        self.configuration = configuration
        self.context = context
        // An injected context may target a device unknown to the caller. Keep the deterministic
        // graph seam and do not guess a mismatched queue/device pair.
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
        self.processingPrefixCache = BoundedLRUCache(
            maxEntries: configuration.processingPrefixMaxEntries,
            maxCostBytes: configuration.processingPrefixMaxCostBytes
        )
    }

    func invalidateLUTDependentCaches() {
        lutCache.removeAll()
        previewCache.removeAll()
    }

    func evictAll() {
        previewCache.removeAll(countAsEvictions: true)
        developedSourceCache.removeAll(countAsEvictions: true)
        processingPrefixCache.removeAll(countAsEvictions: true)
        lutCache.removeAll()
        toneCurveCache.removeAll()
        toneCurveSource = nil
        toneCurveSpace = nil
    }

    func invalidateAll() {
        previewCache.removeAll()
        developedSourceCache.removeAll()
        processingPrefixCache.removeAll()
        toneCurveCache.removeAll()
        toneCurveSource = nil
        toneCurveSpace = nil
    }
}
