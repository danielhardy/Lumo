import Foundation
import AppKit
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import os.lock
import Darwin

/// Filmstrip and file-browser thumbnails.
///
/// **Not part of the render stack, and deliberately not on `RenderEngine`.** These go through
/// `CGImageSource`, which reads a file's embedded preview — for a RAW that is the camera's own JPEG,
/// which is why a 30 MB DNG thumbnails in milliseconds without ever being demosaiced. There is no
/// `CIImage`, no filter graph and no `CIContext` anywhere in here, so routing them through the
/// engine would buy nothing and cost something: thumbnails for a folder would then queue behind
/// every preview render on the actor's single execution context.
///
/// What Step 7 *did* change is what they hang off. Both `ImageCollection` call sites captured
/// `ImageProcessor.shared` — a non-`Sendable` class — into a `Task.detached`, which is the hazard
/// `docs/PHASE2_SPEC.md` §2 flags and the thing that kept strict concurrency red. These are
/// stateless statics on a caseless `enum`, so nothing crosses the boundary but a `URL` or a `Data`.
///
/// `NSImage` is the return type because the filmstrip is AppKit and that is where these land. It is
/// not `Sendable`, so the *call* belongs off the main actor and the result is published on it —
/// which is exactly what `ImageCollection` does.
enum Thumbnails {

    /// The filmstrip's thumbnail size, in pixels on the long edge.
    static let defaultMaxPixelSize = 240

    /// Thumbnails are small, but a long folder navigation session can otherwise retain one image per
    /// file forever. The cache stores PNG bytes, not `NSImage`, so its cost is measurable and the
    /// value never crosses the lock as a mutable AppKit object.
    private static let cache = ThumbnailByteCache(maxEntries: 256, maxCostBytes: 32 * 1024 * 1024)

    static func cacheStatistics() -> CacheStatistics { cache.statistics }

    /// Used by the render engine's memory-pressure observer and by deterministic tests.
    static func evictForMemoryPressure() { cache.removeAll(countAsEviction: true) }

    /// Clears entries while retaining cumulative counters. This is useful when a source folder is
    /// rescanned and also prevents tests from depending on another test's cache contents.
    static func invalidateCache() { cache.removeAll(countAsEviction: false) }

    /// Generate a thumbnail from a file, using the embedded preview where there is one.
    static func generate(from url: URL, maxPixelSize: Int = defaultMaxPixelSize) -> NSImage? {
        guard maxPixelSize > 0 else { return nil }
        // Nanosecond-precision stat fields, not file content: a full read here would force every
        // thumbnail request — cache hits included — to load the whole RAW into memory, which is
        // exactly the cost the embedded-preview path above exists to avoid.
        let fingerprint = statFingerprint(for: url)
        let key = cacheKey(
            source: "url:\(url.standardizedFileURL.path):\(fingerprint)",
            maxPixelSize: maxPixelSize
        )
        if let data = cache.value(for: key), let image = image(fromPNG: data) {
            LumoObservability.event(.cacheHit, quality: .thumbnail, detail: "layer=thumbnail")
            return image
        }
        LumoObservability.event(.cacheMiss, quality: .thumbnail, detail: "layer=thumbnail")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(from: source, maxPixelSize: maxPixelSize, cacheKey: key)
    }

    /// Generate a thumbnail from in-memory data (Photos imports).
    static func generate(from data: Data, maxPixelSize: Int = defaultMaxPixelSize) -> NSImage? {
        var interval = LumoSignpostInterval(
            .photoThumbnail,
            context: LumoTraceContext(sourceFingerprint: "data:" + String(data.count), quality: "thumbnail")
        )
        defer { interval.end() }
        guard maxPixelSize > 0 else { return nil }
        let sourceIdentity = ImageSource(data: data, nativeExtent: .zero)
        let key = cacheKey(source: RenderSourceFingerprint(sourceIdentity).value, maxPixelSize: maxPixelSize)
        if let data = cache.value(for: key), let image = image(fromPNG: data) {
            LumoObservability.event(.cacheHit, quality: .thumbnail, detail: "layer=thumbnail")
            return image
        }
        LumoObservability.event(.cacheMiss, quality: .thumbnail, detail: "layer=thumbnail")
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: source, maxPixelSize: maxPixelSize, cacheKey: key)
    }

    private static func thumbnail(
        from source: CGImageSource, maxPixelSize: Int, cacheKey: String?
    ) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Bakes the EXIF orientation into the thumbnail, matching
            // `ImageDecoder.orientedLoadOptions` on the canvas side. Without it the filmstrip
            // contradicts the preview for every portrait JPEG.
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        if let cacheKey, let png = pngData(for: cgImage) {
            cache.insert(png, for: cacheKey)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// A cheap identity for a URL-backed file: device/inode/size/mtime/ctime, mirroring
    /// `ImageSource.cacheFingerprint`'s POSIX fingerprint. No content read, so it stays fast for the
    /// large RAWs this cache exists to make cheap to revisit.
    private static func statFingerprint(for url: URL) -> String {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            path.map { lstat($0, &info) } ?? -1
        }
        guard result == 0 else { return "missing" }
        return [
            String(info.st_dev), String(info.st_ino), String(info.st_size),
            String(info.st_mtimespec.tv_sec), String(info.st_mtimespec.tv_nsec),
            String(info.st_ctimespec.tv_sec), String(info.st_ctimespec.tv_nsec),
        ].joined(separator: ":")
    }

    private static func cacheKey(source: String, maxPixelSize: Int) -> String {
        "thumbnail-v\(RenderPipeline.cacheVersion):\(source):\(maxPixelSize)"
    }

    private static func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func image(fromPNG data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

/// A small synchronous, lock-protected byte cache for the thumbnail API. `OSAllocatedUnfairLock`
/// makes the synchronization explicit and keeps the cache safe when folder thumbnails are generated
/// by detached tasks, without weakening Swift 6's Sendable checking.
private final class ThumbnailByteCache: Sendable {
    private struct State: Sendable {
        var entries: [String: Data] = [:]
        var costs: [String: Int] = [:]
        var recency: [String] = []
        var totalCost = 0
        var hits = 0
        var misses = 0
        var evictions = 0
    }

    private let maxEntries: Int
    private let maxCostBytes: Int
    private let state: OSAllocatedUnfairLock<State>

    init(maxEntries: Int, maxCostBytes: Int) {
        self.maxEntries = max(0, maxEntries)
        self.maxCostBytes = max(0, maxCostBytes)
        self.state = OSAllocatedUnfairLock(initialState: State())
    }

    func value(for key: String) -> Data? {
        state.withLock { state in
            guard let value = state.entries[key] else {
                state.misses += 1
                return nil
            }
            state.hits += 1
            state.recency.removeAll { $0 == key }
            state.recency.append(key)
            return value
        }
    }

    func insert(_ data: Data, for key: String) {
        state.withLock { state in
            if let oldCost = state.costs.removeValue(forKey: key) {
                state.totalCost -= oldCost
                state.entries.removeValue(forKey: key)
                state.recency.removeAll { $0 == key }
            }
            let cost = data.count
            guard maxEntries > 0, maxCostBytes > 0, cost <= maxCostBytes else {
                if cost > maxCostBytes { state.evictions += 1 }
                return
            }
            state.entries[key] = data
            state.costs[key] = cost
            state.recency.append(key)
            state.totalCost += cost
            while state.entries.count > maxEntries || state.totalCost > maxCostBytes {
                guard let oldest = state.recency.first else { break }
                state.recency.removeFirst()
                state.totalCost -= state.costs.removeValue(forKey: oldest) ?? 0
                state.entries.removeValue(forKey: oldest)
                state.evictions += 1
            }
        }
    }

    func removeAll(countAsEviction: Bool) {
        state.withLock { state in
            if countAsEviction { state.evictions += state.entries.count }
            state.entries.removeAll(keepingCapacity: true)
            state.costs.removeAll(keepingCapacity: true)
            state.recency.removeAll(keepingCapacity: true)
            state.totalCost = 0
        }
    }

    var statistics: CacheStatistics {
        state.withLock { state in
            CacheStatistics(
                hits: state.hits, misses: state.misses, evictions: state.evictions,
                count: state.entries.count, costBytes: state.totalCost
            )
        }
    }
}
