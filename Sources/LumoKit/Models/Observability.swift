import Foundation
import os.log
import CryptoKit

/// The stable vocabulary used by the Points of Interest instrument.
///
/// Keep these names static: Instruments groups intervals by signpost name, and a stable vocabulary
/// makes captures comparable across builds. The values attached to an interval are intentionally
/// coarse and private-safe; they never contain a filename, URL, or metadata dictionary.
enum LumoWorkflowStage: CaseIterable {
    case launch
    case scan
    case decode
    case render
    case cache
    case photoSwitch
    case histogram
    case export
    case liveEdit
    case photoTransfer
    case photoThumbnail
    case photoCollectionInsert

    var name: StaticString {
        switch self {
        case .launch: return "Launch"
        case .scan: return "Scan"
        case .decode: return "Decode"
        case .render: return "Render"
        case .cache: return "Cache"
        case .photoSwitch: return "PhotoSwitch"
        case .histogram: return "Histogram"
        case .export: return "Export"
        case .liveEdit: return "LiveEdit"
        case .photoTransfer: return "PhotoTransfer"
        case .photoThumbnail: return "PhotoThumbnail"
        case .photoCollectionInsert: return "PhotoCollectionInsert"
        }
    }
}

enum LumoWorkflowEvent: CaseIterable {
    case cacheHit
    case cacheMiss
    case cancellation
    case coalesced
    case pointerInput
    case renderStart
    case renderEnd
    case gpuComplete
    case presentationEncoded
    case drawablePresented
    case staleRevision

    var name: StaticString {
        switch self {
        case .cacheHit: return "CacheHit"
        case .cacheMiss: return "CacheMiss"
        case .cancellation: return "Cancellation"
        case .coalesced: return "Coalesced"
        case .pointerInput: return "PointerInput"
        case .renderStart: return "RenderStart"
        case .renderEnd: return "RenderEnd"
        case .gpuComplete: return "GPUComplete"
        case .presentationEncoded: return "PresentationEncoded"
        case .drawablePresented: return "DrawablePresented"
        case .staleRevision: return "StaleRevision"
        }
    }
}

/// Safe identifiers for signpost arguments.
///
/// A source token is a truncated SHA-256 digest of the existing cache fingerprint. It helps match
/// events for one photo within a trace while ensuring that a user's path is never emitted to the
/// unified log. Quality remains a human-readable enum so interactive, settled, and export work can
/// be separated in Instruments.
struct LumoTraceContext: Sendable, Equatable {
    let sourceToken: String
    let quality: String

    init(source: ImageSource, quality: RenderQuality) {
        self.init(sourceToken: source.traceToken, quality: quality.rawValue)
    }

    init(sourceFingerprint: String, quality: String) {
        let digest = SHA256.hash(data: Data(sourceFingerprint.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        self.sourceToken = String(digest.prefix(16))
        self.quality = quality
    }

    init(sourceToken: String, quality: String) {
        self.sourceToken = sourceToken
        self.quality = quality
    }

    static let unknown = Self(sourceFingerprint: "unknown", quality: "unknown")
}

/// A small wrapper that makes begin/end pairing explicit at every early return and throw site.
/// Callers hold it as a local variable and use `defer { interval.end() }`.
struct LumoSignpostInterval {
    private let signposter: OSSignposter
    private let stage: LumoWorkflowStage
    private let state: OSSignpostIntervalState
    private var isEnded = false

    init(_ stage: LumoWorkflowStage, context: LumoTraceContext = .unknown) {
        self.signposter = OSSignposter(subsystem: "com.lumo.app", category: "workflow")
        self.stage = stage
        self.state = signposter.beginInterval(
            stage.name,
            "source=\(context.sourceToken, privacy: .public) quality=\(context.quality, privacy: .public)"
        )
    }

    mutating func end() {
        guard !isEnded else { return }
        isEnded = true
        signposter.endInterval(stage.name, state)
    }
}

enum LumoObservability {
    private static let signposter = OSSignposter(subsystem: "com.lumo.app", category: "workflow")

    static func begin(
        _ stage: LumoWorkflowStage,
        source: ImageSource? = nil,
        quality: RenderQuality? = nil
    ) -> LumoSignpostInterval {
        LumoSignpostInterval(
            stage,
            context: source.map { LumoTraceContext(source: $0, quality: quality ?? .preview) }
                ?? .unknown
        )
    }

    static func event(
        _ event: LumoWorkflowEvent,
        source: ImageSource? = nil,
        quality: RenderQuality? = nil,
        detail: String = ""
    ) {
        let context = source.map { LumoTraceContext(source: $0, quality: quality ?? .preview) }
            ?? .unknown
        signposter.emitEvent(
            event.name,
            "source=\(context.sourceToken, privacy: .public) quality=\(context.quality, privacy: .public) detail=\(detail, privacy: .public)"
        )
    }

    /// Hash an input name without ever passing it to an OSLog interpolation. Used before an
    /// `ImageSource` exists, during the eager open-time decode.
    static func sourceToken(forInput input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(16))
    }

    static func liveEdit(_ event: LumoWorkflowEvent, source: ImageSource, quality: RenderQuality,
                         revision: UInt64, detail: String = "") {
        self.event(event, source: source, quality: quality,
                   detail: "revision=\(revision) \(detail)")
    }
}
