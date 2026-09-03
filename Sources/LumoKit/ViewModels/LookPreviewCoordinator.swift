import CoreGraphics
import Foundation
import ImageIO

/// Compact geometry shared by the Look browser and its renderer.
///
/// The browser displays this at roughly 84×56 points. Rendering at 2× keeps the preview crisp on a
/// Retina inspector while remaining small enough that a long Look list cannot allocate full-size
/// copies of the source image.
enum LookPreviewLayout {
    static let displaySize = CGSize(width: 84, height: 56)
    static let renderSize = CGSize(width: 168, height: 112)
    static let rowMinHeight: CGFloat = 72
    static let cacheMaxEntries = 24
    static let cacheMaxCostBytes = 8 * 1024 * 1024
}

/// Main-actor owner for the Look browser's lazy thumbnails.
///
/// Look previews are separate from the active preview coordinator: selecting a Look must remain
/// the only operation that changes the edit document or history. Requests still use the shared
/// RenderEngine pipeline, so RAW development, global edits, LUT interpolation, and crop ordering
/// are identical to the main canvas.
@MainActor
final class LookPreviewCoordinator {

    struct CacheKey: Hashable, Sendable {
        let source: RenderSourceFingerprint
        let documentHash: String
        let lutFingerprint: String
        let widthBits: UInt64
        let heightBits: UInt64

        init(source: ImageSource, document: EditDocument, look: CubeLUT, targetSize: CGSize) {
            self.source = RenderSourceFingerprint(source)
            self.documentHash = document.editHash
            self.lutFingerprint = look.cacheFingerprint
            self.widthBits = Double(targetSize.width).bitPattern
            self.heightBits = Double(targetSize.height).bitPattern
        }
    }

    private let engine: any RenderEngining
    private let scheduler: ImageWorkScheduler
    private let cache = BoundedLRUCache<CacheKey, CGImage>(
        maxEntries: LookPreviewLayout.cacheMaxEntries,
        maxCostBytes: LookPreviewLayout.cacheMaxCostBytes
    )
    private var inFlight: [CacheKey: Task<CGImage?, Never>] = [:]
    private var nextJobNumber = 0

    init(engine: any RenderEngining, scheduler: ImageWorkScheduler) {
        self.engine = engine
        self.scheduler = scheduler
    }

    /// Render one candidate Look without touching the active document.
    ///
    /// `nil` means no source is currently available or the render failed. The view owns the
    /// presentation fallback so a missing/invalid preview can never remove a Look row.
    func image(
        source: ImageSource?,
        document: EditDocument,
        look: CubeLUT,
        targetSize: CGSize = LookPreviewLayout.renderSize
    ) async -> CGImage? {
        guard let source, Self.isValid(targetSize) else { return nil }

        var previewDocument = document
        // Compare Look character at full strength, independent of the selected Look's slider.
        previewDocument.lut = LUTSettings(lutID: look.lutID, intensity: 1)
        let key = CacheKey(
            source: source, document: previewDocument, look: look, targetSize: targetSize
        )

        if let cached = cache.value(for: key) { return cached }
        if let existing = inFlight[key] { return await existing.value }

        nextJobNumber &+= 1
        let jobID = ImageWorkScheduler.JobID("look-preview-\(nextJobNumber)-\(look.lutID.raw)")
        let request = RenderRequest(
            source: source,
            document: previewDocument,
            lut: look,
            targetSize: targetSize,
            quality: .thumbnail,
            output: .raster,
            space: .current
        )

        let task = Task { @MainActor [engine, scheduler] in
            await withCheckedContinuation { continuation in
                let admitted = scheduler.enqueue(
                    id: jobID,
                    lane: .thumbnail,
                    priority: .visibleGrid
                ) {
                    let image: CGImage?
                    if let result = try? await engine.render(request),
                       let source = CGImageSourceCreateWithData(result.data as CFData, nil) {
                        image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                    } else {
                        image = nil
                    }
                    continuation.resume(returning: image)
                }
                if !admitted {
                    continuation.resume(returning: nil)
                }
            }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight.removeValue(forKey: key)

        if let image {
            cache.insert(image, for: key, cost: Self.cost(of: image))
        }
        return image
    }

    var statistics: CacheStatistics { cache.statistics }

    private static func isValid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func cost(of image: CGImage) -> Int {
        let pixels = image.width.multipliedReportingOverflow(by: image.height)
        guard !pixels.overflow else { return Int.max }
        let bytes = pixels.partialValue.multipliedReportingOverflow(by: 4)
        return bytes.overflow ? Int.max : bytes.partialValue
    }
}

