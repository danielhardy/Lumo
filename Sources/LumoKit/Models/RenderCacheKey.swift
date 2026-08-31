import Foundation
import CryptoKit

/// Stable identity for a source as it exists now.
///
/// URL-backed sources use file resource metadata so editing a file in place cannot reuse a stale
/// result. Data-backed sources carry their content digest in `ImageSource`, avoiding a hash of the
/// same Photos payload on every slider tick.
struct RenderSourceFingerprint: Hashable, Sendable {
    let value: String

    init(_ source: ImageSource) {
        self.value = source.cacheFingerprint
    }
}

/// The exact scale dimensions used by a render. `RenderScale` is intentionally a small policy enum,
/// not a cache key, because it is not `Hashable` and because quality remains meaningful even when
/// two tiers happen to use the same pixel box.
struct RenderScaleKey: Hashable, Sendable {
    let isFull: Bool
    let widthBits: UInt64
    let heightBits: UInt64

    init(_ scale: RenderScale) {
        switch scale {
        case .full:
            isFull = true
            widthBits = 0
            heightBits = 0
        case .preview(let size), .interactive(let size, _):
            isFull = false
            widthBits = Double(size.width).bitPattern
            heightBits = Double(size.height).bitPattern
        }
    }
}

/// Cache identity for the source stage. It excludes adjustments and LUTs because those are applied
/// after the developed source has been built.
struct DevelopedSourceCacheKey: Hashable, Sendable {
    let source: RenderSourceFingerprint
    let developHash: String
    let scale: RenderScaleKey
    let pipelineVersion: Int
}

/// Cache identity for a display raster. Full-resolution/export requests never create this key.
struct PreviewCacheKey: Hashable, Sendable {
    let source: RenderSourceFingerprint
    let documentHash: String
    let lutFingerprint: String
    let targetScale: RenderScaleKey
    let quality: RenderQuality
    let space: WorkingSpace
    let pipelineVersion: Int
}

enum RenderCacheHash {
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // A fixed fallback would let two different values that both fail to encode (e.g. a
        // non-conforming Double such as .nan) collide on the same cache key and serve each other's
        // pixels. A fresh identity per failure guarantees a miss instead — safe, just uncached.
        guard let data = try? encoder.encode(value) else { return "encoding-failed:\(UUID())" }
        return digest(data)
    }
}
