import CoreGraphics
import Foundation

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
    static let renderDelay: Duration = .milliseconds(60)
}

/// Main-actor owner for the Look browser's lazy thumbnails.
///
/// Look previews are separate from the active preview coordinator: selecting a Look must remain
/// the only operation that changes the edit document or history. Requests still use the shared
/// RenderEngine pipeline, so RAW development, global edits, LUT interpolation, and crop ordering
/// are identical to the main canvas.
@MainActor
final class LookPreviewCoordinator {

    @MainActor
    private final class RenderBox {
        var image: CGImage?
    }

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

    private struct WorkKey: Hashable, Sendable {
        let source: RenderSourceFingerprint
        let lutFingerprint: String
        let widthBits: UInt64
        let heightBits: UInt64

        init(source: ImageSource, look: CubeLUT, targetSize: CGSize) {
            self.source = RenderSourceFingerprint(source)
            self.lutFingerprint = look.cacheFingerprint
            self.widthBits = Double(targetSize.width).bitPattern
            self.heightBits = Double(targetSize.height).bitPattern
        }

        /// One logical scheduler slot per source/Look/viewport. Document generations replace this
        /// slot instead of creating a second queued job for the same thumbnail.
        var schedulerID: ImageWorkScheduler.JobID {
            let value = [
                source.value, lutFingerprint, String(widthBits), String(heightBits),
            ].joined(separator: "|")
            return ImageWorkScheduler.JobID(
                "look-preview-\(RenderCacheHash.digest(Data(value.utf8)))"
            )
        }
    }

    private struct InFlight {
        let task: Task<CGImage?, Never>
        let jobID: ImageWorkScheduler.JobID
        let token: UInt64
        let cacheKey: CacheKey
    }

    private var inFlight: [WorkKey: InFlight] = [:]
    private var nextToken: UInt64 = 0

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
        let workKey = WorkKey(source: source, look: look, targetSize: targetSize)

        if let cached = cache.value(for: key) { return cached }
        if let existing = inFlight[workKey], existing.cacheKey == key {
            return await withTaskCancellationHandler(
                operation: {
                    await existing.task.value
                },
                onCancel: {
                    existing.task.cancel()
                    Task { @MainActor in
                        scheduler.cancel(id: existing.jobID)
                    }
                })
        }

        // A document revision changes the pixels, but not the logical source/Look slot. Cancel its
        // previous generation before admission so a rapid edit burst leaves at most one queued or
        // running thumbnail for this row. The token keeps an older task from removing the newer
        // generation from `inFlight` after its cancellation callback returns.
        if let existing = inFlight[workKey] {
            scheduler.cancel(id: existing.jobID, pump: false)
            existing.task.cancel()
            inFlight.removeValue(forKey: workKey)
        }

        nextToken &+= 1
        let token = nextToken
        let jobID = workKey.schedulerID
        let request = RenderRequest(
            source: source,
            document: previewDocument,
            lut: look,
            targetSize: targetSize,
            quality: .thumbnail,
            output: .raster,
            space: .current
        )

        let task = Task<CGImage?, Never> { @MainActor [engine, scheduler] in
            // The row task identity can change on every pointer tick. Hold admission for the same
            // quiet period used by the editor so those transient generations are cancelled before
            // they reach the thumbnail lane.
            try? await Task.sleep(for: LookPreviewLayout.renderDelay)
            guard !Task.isCancelled else { return nil }
            return await withTaskCancellationHandler(
                operation: {
                    await withCheckedContinuation {
                        (continuation: CheckedContinuation<CGImage?, Never>) in
                        let rendered = RenderBox()
                        let admitted = scheduler.enqueue(
                            id: jobID,
                            lane: .thumbnail,
                            priority: .visibleGrid,
                            onTerminal: { outcome in
                                continuation.resume(
                                    returning: outcome == .completed ? rendered.image : nil
                                )
                            }
                        ) {
                            // RenderEngine creates the CGImage beside its CIContext. This avoids the
                            // PNG encode/decode round trip that the Sendable `render` boundary needs.
                            rendered.image = await engine.makeCGImage(request)
                        }
                        // Cancellation can race the task's first hop onto the main actor. Check here
                        // as well as in the handler so a job admitted after that hop cannot be left
                        // queued behind a cancellation that already happened.
                        if Task.isCancelled && admitted {
                            scheduler.cancel(id: jobID)
                        }
                    }
                },
                onCancel: {
                    Task { @MainActor in
                        scheduler.cancel(id: jobID)
                    }
                })
        }
        inFlight[workKey] = InFlight(
            task: task, jobID: jobID, token: token, cacheKey: key
        )
        let image = await withTaskCancellationHandler(
            operation: {
                await task.value
            },
            onCancel: {
                task.cancel()
                Task { @MainActor in
                    scheduler.cancel(id: jobID)
                }
            })
        if inFlight[workKey]?.token == token {
            inFlight.removeValue(forKey: workKey)
        }

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
