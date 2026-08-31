import CryptoKit
import Foundation

/// A durable identity for a photo source.
///
/// File identities prefer the filesystem resource identifier, which survives a move on the same
/// volume. A canonical path is the fallback for URLs that do not currently resolve to a file (and
/// for filesystems that do not provide a resource identifier). Data-only imports use the SHA-256 of
/// their bytes. This is deliberately content-addressed only for data that is already in memory;
/// folder scans use `PhotoSourceFingerprint` rather than reading an entire RAW file.
struct PhotoAssetID: Codable, Hashable, Sendable, Equatable, CustomStringConvertible {
    private let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Stable identity for a file URL. The path fallback keeps this useful for missing/relinking
    /// records and makes two unresolved URLs distinct even when they have the same contents.
    static func file(_ url: URL) -> PhotoAssetID {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let fingerprint = PhotoSourceFingerprint.file(at: canonical)
        if let resourceID = fingerprint.resourceIdentifier {
            return PhotoAssetID(rawValue: "file-resource:\(resourceID)")
        }
        return PhotoAssetID(rawValue: "file-path:\(canonical.path)")
    }

    /// Identity for a Photos/local-library identifier supplied by the caller. Unlike a generated
    /// UUID, an Apple Photos local identifier is durable across launches and does not depend on the
    /// imported bytes being delivered in exactly the same representation.
    static func photos(localIdentifier: String) -> PhotoAssetID {
        PhotoAssetID(rawValue: "photos:\(localIdentifier)")
    }

    /// Durable identity for a data-only import. Identical bytes intentionally identify one logical
    /// source; callers with two distinct Photos assets should use `photos(localIdentifier:)`.
    static func data(_ data: Data) -> PhotoAssetID {
        PhotoAssetID(rawValue: "data:\(Self.sha256Hex(data))")
    }

    /// Compatibility identity for a transient import whose provider has no durable identifier.
    /// New data-only imports should use `data(_:)`, as `imported(_:)` is only stable for the life of
    /// the UUID supplied by its caller.
    static func imported(_ id: UUID) -> PhotoAssetID {
        PhotoAssetID(rawValue: "import:\(id.uuidString.lowercased())")
    }

    var raw: String { rawValue }
    var description: String { rawValue }

    fileprivate static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A bounded source signature used in cache keys and source-change detection.
///
/// The filesystem resource identifier catches replacement-by-atomic-write on normal macOS
/// volumes. Size, modification time, and a digest of the first/last 64 KiB cover in-place edits
/// without turning every folder scan into a full RAW-file hash. A caller that needs cryptographic
/// identity for already-available bytes can use `PhotoSourceFingerprint.data(_:)`.
struct PhotoSourceFingerprint: Codable, Hashable, Sendable, Equatable {
    static let sampleSize = 64 * 1024

    let byteCount: Int64?
    let modificationDate: Date?
    let resourceIdentifier: String?
    let sampleDigest: String?

    static func file(at url: URL) -> PhotoSourceFingerprint {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey
        ])
        let resourceIdentifier = values?.fileResourceIdentifier.map(String.init(describing:))
        let byteCount = values?.fileSize.map(Int64.init)
        let modificationDate = values?.contentModificationDate
        let sampleDigest = sampleDigest(at: url, byteCount: byteCount)
        return PhotoSourceFingerprint(
            byteCount: byteCount,
            modificationDate: modificationDate,
            resourceIdentifier: resourceIdentifier,
            sampleDigest: sampleDigest
        )
    }

    static func data(_ data: Data) -> PhotoSourceFingerprint {
        PhotoSourceFingerprint(
            byteCount: Int64(data.count),
            modificationDate: nil,
            resourceIdentifier: nil,
            sampleDigest: PhotoAssetID.sha256Hex(data)
        )
    }

    /// A stable printable key for caches. It includes every observed component, including missing
    /// values, so an unavailable file never aliases a successfully fingerprinted one.
    var cacheKey: String {
        [
            byteCount.map(String.init) ?? "?",
            modificationDate.map { String(format: "%.6f", $0.timeIntervalSinceReferenceDate) } ?? "?",
            resourceIdentifier ?? "?",
            sampleDigest ?? "?",
        ].joined(separator: ":")
    }

    /// Whether two observations can be treated as the same source after a path change. Resource
    /// identity is strongest; the bounded signature is the fallback for volumes that do not expose
    /// one. This is intentionally a matching hint for relinking, not a claim of full-file equality.
    func matches(_ other: PhotoSourceFingerprint) -> Bool {
        if let resourceIdentifier, let otherResourceIdentifier = other.resourceIdentifier {
            return resourceIdentifier == otherResourceIdentifier
                && byteCount == other.byteCount
                && modificationDate == other.modificationDate
                && sampleDigest == other.sampleDigest
        }
        return byteCount == other.byteCount
            && modificationDate == other.modificationDate
            && sampleDigest == other.sampleDigest
    }

    private static func sampleDigest(at url: URL, byteCount: Int64?) -> String? {
        guard let byteCount, byteCount >= 0,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            let first = try handle.read(upToCount: sampleSize) ?? Data()
            var sample = first
            if byteCount > Int64(sampleSize) {
                try handle.seek(toOffset: UInt64(max(0, byteCount - Int64(sampleSize))))
                sample.append(try handle.read(upToCount: sampleSize) ?? Data())
            }
            return PhotoAssetID.sha256Hex(sample)
        } catch {
            return nil
        }
    }
}

/// How a discovered source can be reopened. The bookmark is kept with the source record rather
/// than in mutable library state, because it describes the source itself and enables relinking.
struct PhotoAssetSource: Codable, Hashable, Sendable, Equatable {
    let id: PhotoAssetID
    let url: URL?
    let data: Data?
    let bookmarkData: Data?
    let fingerprint: PhotoSourceFingerprint

    init(
        url: URL,
        bookmarkData: Data? = nil,
        fingerprint: PhotoSourceFingerprint? = nil
    ) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        self.id = PhotoAssetID.file(canonical)
        self.url = canonical
        self.data = nil
        self.bookmarkData = bookmarkData
        self.fingerprint = fingerprint ?? PhotoSourceFingerprint.file(at: canonical)
    }

    init(
        data: Data,
        id: PhotoAssetID? = nil
    ) {
        self.id = id ?? PhotoAssetID.data(data)
        self.url = nil
        self.data = data
        self.bookmarkData = nil
        self.fingerprint = PhotoSourceFingerprint.data(data)
    }

    /// Mint a security-scoped bookmark when the caller has authority to persist one. Failure is
    /// non-fatal: the path and fingerprint still support the normal in-session workflow.
    static func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    var cacheKey: String { "\(id.description)|\(fingerprint.cacheKey)" }

    func matches(_ other: PhotoAssetSource) -> Bool {
        fingerprint.matches(other.fingerprint)
    }
}

/// Pixel dimensions are kept as integers so the library model remains Codable and independent of
/// Core Graphics.
struct PhotoPixelDimensions: Codable, Hashable, Sendable, Equatable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// The metadata needed by the library and inspector. `ImageMetadata` remains the display-oriented
/// reader; this record is the stable value snapshot stored with an asset.
struct PhotoAssetMetadata: Codable, Hashable, Sendable, Equatable {
    let dimensions: PhotoPixelDimensions?
    let captureDate: String?
    let cameraMake: String?
    let cameraModel: String?
    let lens: String?

    init(
        dimensions: PhotoPixelDimensions? = nil,
        captureDate: String? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lens: String? = nil
    ) {
        self.dimensions = dimensions
        self.captureDate = captureDate
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lens = lens
    }

    init(imageMetadata: ImageMetadata) {
        let dimensions: PhotoPixelDimensions?
        if let width = imageMetadata.pixelWidth, let height = imageMetadata.pixelHeight {
            dimensions = PhotoPixelDimensions(width: width, height: height)
        } else {
            dimensions = nil
        }
        self.init(
            dimensions: dimensions,
            captureDate: imageMetadata.dateTaken,
            cameraMake: imageMetadata.make,
            cameraModel: imageMetadata.model,
            lens: imageMetadata.lens
        )
    }

    static let empty = PhotoAssetMetadata()

    var camera: String? {
        [cameraMake, cameraModel].compactMap { $0 }.joined(separator: " ").nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum PhotoFlag: String, Codable, Hashable, Sendable, Equatable {
    case none
    case pick
    case reject
}

enum PhotoThumbnailState: String, Codable, Hashable, Sendable, Equatable {
    case notRequested
    case loading
    case ready
    case failed
}

/// Mutable library/culling state is separate from the immutable source and metadata snapshot.
struct PhotoAssetLibraryState: Codable, Hashable, Sendable, Equatable {
    private(set) var rating: Int
    var flag: PhotoFlag
    var thumbnail: PhotoThumbnailState

    init(rating: Int = 0, flag: PhotoFlag = .none, thumbnail: PhotoThumbnailState = .notRequested) {
        self.rating = min(max(rating, 0), 5)
        self.flag = flag
        self.thumbnail = thumbnail
    }

    mutating func setRating(_ rating: Int) {
        self.rating = min(max(rating, 0), 5)
    }
}

/// Stable, value-based record for one library asset. Rendered images and AppKit objects are kept
/// outside this type; it is safe to persist, send across actors, and use as a cache/input record.
struct PhotoAsset: Identifiable, Codable, Hashable, Sendable, Equatable {
    let source: PhotoAssetSource
    let filename: String
    let fileType: String
    let metadata: PhotoAssetMetadata
    var libraryState: PhotoAssetLibraryState

    var id: PhotoAssetID { source.id }
    var url: URL? { source.url }
    var bookmarkData: Data? { source.bookmarkData }
    var cacheKey: String { source.cacheKey }

    // Convenience accessors keep the record pleasant to use from a grid/culling model while the
    // stored representation remains split into immutable source/metadata and mutable library state.
    var dimensions: PhotoPixelDimensions? { metadata.dimensions }
    var captureDate: String? { metadata.captureDate }
    var camera: String? { metadata.camera }
    var lens: String? { metadata.lens }
    var rating: Int {
        get { libraryState.rating }
        set { libraryState.setRating(newValue) }
    }
    var flag: PhotoFlag {
        get { libraryState.flag }
        set { libraryState.flag = newValue }
    }
    var thumbnailState: PhotoThumbnailState {
        get { libraryState.thumbnail }
        set { libraryState.thumbnail = newValue }
    }

    init(
        source: PhotoAssetSource,
        filename: String,
        fileType: String,
        metadata: PhotoAssetMetadata = .empty,
        libraryState: PhotoAssetLibraryState = PhotoAssetLibraryState()
    ) {
        self.source = source
        self.filename = filename
        self.fileType = fileType.lowercased()
        self.metadata = metadata
        self.libraryState = libraryState
    }

    init(
        url: URL,
        filename: String? = nil,
        metadata: PhotoAssetMetadata = .empty,
        libraryState: PhotoAssetLibraryState = PhotoAssetLibraryState(),
        bookmarkData: Data? = nil
    ) {
        self.init(
            source: PhotoAssetSource(url: url, bookmarkData: bookmarkData),
            filename: filename ?? url.deletingPathExtension().lastPathComponent,
            fileType: url.pathExtension,
            metadata: metadata,
            libraryState: libraryState
        )
    }

    init(
        data: Data,
        filename: String,
        fileType: String? = nil,
        metadata: PhotoAssetMetadata = .empty,
        libraryState: PhotoAssetLibraryState = PhotoAssetLibraryState()
    ) {
        self.init(
            source: PhotoAssetSource(data: data),
            filename: filename,
            fileType: fileType ?? URL(fileURLWithPath: filename).pathExtension,
            metadata: metadata,
            libraryState: libraryState
        )
    }

    /// Build a record from ImageIO's existing metadata reader without putting that reader or any
    /// Core Graphics object into the record itself.
    static func discoveredFile(at url: URL, bookmarkData: Data? = nil) -> PhotoAsset {
        let imageMetadata = ImageMetadata.read(from: url)
        return PhotoAsset(
            url: url,
            metadata: PhotoAssetMetadata(imageMetadata: imageMetadata),
            bookmarkData: bookmarkData ?? PhotoAssetSource.bookmarkData(for: url)
        )
    }
}

typealias PhotoAssetState = PhotoAssetLibraryState
typealias PixelDimensions = PhotoPixelDimensions
