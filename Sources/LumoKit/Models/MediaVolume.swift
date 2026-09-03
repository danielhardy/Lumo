import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A mounted, removable volume that contains at least one file Lumo can open.
///
/// This is deliberately a value rather than a `URL` list owned by the view.  It is the seam used
/// by tests to describe fixture volumes and keeps hardware discovery out of the selector UI.
struct MediaVolume: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let bookmarkData: Data?

    init(id: String? = nil, name: String, url: URL, bookmarkData: Data? = nil) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        self.id = id ?? canonical.path
        self.name = name
        self.url = canonical
        self.bookmarkData = bookmarkData
    }

    /// Resolve a bookmark granted by an Open panel before touching the volume. Discovery can
    /// produce a raw mount URL, while a sandbox fallback produces a security-scoped URL.
    func resolvedAccessURL() -> URL {
        guard let bookmarkData else { return url }
        var isStale = false
        return (try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )) ?? url
    }
}

/// One image admitted by a removable-volume scan.  The selector gets display-ready metadata here,
/// while the collection later builds the normal `PhotoAsset` record from the same URL.
struct MediaVolumeFile: Identifiable, Sendable, Equatable {
    let id: String
    let url: URL
    let filename: String
    let orientation: Int
    let metadata: ImageMetadata

    init(url: URL, filename: String? = nil, orientation: Int = 1,
         metadata: ImageMetadata = ImageMetadata()) {
        self.url = url.standardizedFileURL
        self.id = self.url.path
        self.filename = filename ?? url.lastPathComponent
        self.orientation = orientation
        self.metadata = metadata
    }

    var orientationLabel: String {
        switch orientation {
        case 3: return "180°"
        case 6: return "90°"
        case 8: return "270°"
        case 5, 7: return "Rotated"
        default: return ""
        }
    }

    var metadataSummary: String? {
        let camera = [metadata.make, metadata.model].compactMap { $0 }.joined(separator: " ")
        let dimensions: String? = if let width = metadata.pixelWidth, let height = metadata.pixelHeight {
            "\(width) × \(height)"
        } else {
            nil
        }
        let values = [camera.nilIfEmpty, dimensions, metadata.lens].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: "  ·  ")
    }
}

struct MediaVolumeScanResult: Sendable, Equatable {
    let files: [MediaVolumeFile]
    let warnings: [String]
}

/// Selection state for the image-first volume sheet. Keeping this independent of SwiftUI makes
/// select-all/none, toggle, and cancellation behavior deterministic in tests.
struct MediaVolumeSelectionModel: Sendable, Equatable {
    private(set) var selectedIDs: Set<String> = []

    var count: Int { selectedIDs.count }

    mutating func selectAll(in files: [MediaVolumeFile]) {
        selectedIDs = Set(files.map(\.id))
    }

    mutating func clear() {
        selectedIDs.removeAll()
    }

    mutating func toggle(_ file: MediaVolumeFile) {
        if !selectedIDs.insert(file.id).inserted {
            selectedIDs.remove(file.id)
        }
    }

    func contains(_ file: MediaVolumeFile) -> Bool {
        selectedIDs.contains(file.id)
    }
}

enum MediaVolumeError: LocalizedError, Sendable, Equatable {
    case permissionDenied(String)
    case volumeRemoved(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let name): return "Permission denied for \(name)."
        case .volumeRemoved(let name): return "\(name) is no longer available."
        case .unreadable(let name): return "Can't read \(name)."
        }
    }
}

/// Discovery and scanning are injected so removable-media behavior can be exercised with fixture
/// volumes and failure-injecting fakes. The production implementation never writes to a volume.
protocol MediaVolumeProviding: Sendable {
    /// Whether a permission failure can be recovered by asking the user to select the volume in
    /// an Open panel. Fixture providers leave this false so tests never present AppKit UI.
    var supportsInteractiveAccessGrant: Bool { get }
    func discover() async -> [MediaVolume]
    func scan(_ volume: MediaVolume) async throws -> MediaVolumeScanResult
}

extension MediaVolumeProviding {
    var supportsInteractiveAccessGrant: Bool { false }
}

struct MountedMediaVolumeProvider: MediaVolumeProviding {
    let supportsInteractiveAccessGrant = true

    func discover() async -> [MediaVolume] {
        await Task.detached(priority: .utility) {
            Self.discoverMountedVolumes()
        }.value
    }

    func scan(_ volume: MediaVolume) async throws -> MediaVolumeScanResult {
        try await Task.detached(priority: .utility) {
            try Self.scanMountedVolume(volume)
        }.value
    }

    private static func discoverMountedVolumes() -> [MediaVolume] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsRemovable == true || values.volumeIsEjectable == true else {
                return nil
            }
            // With the removable-media entitlement, most mounts are readable here. If the
            // entitlement is unavailable or macOS requires a user grant, keep the volume visible
            // so scan() can recover through the Open panel instead of hiding the device.
            let isReadable = FileManager.default.isReadableFile(atPath: url.path)
            guard !isReadable || containsSupportedFile(in: url) else { return nil }
            let name = values.volumeName?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? url.lastPathComponent
            return MediaVolume(
                name: name, url: url, bookmarkData: PhotoAssetSource.bookmarkData(for: url)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func containsSupportedFile(in url: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return false }
        while let candidate = enumerator.nextObject() as? URL {
            guard let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            if supports(candidate) && FileManager.default.isReadableFile(atPath: candidate.path) {
                return true
            }
        }
        return false
    }

    private static func scanMountedVolume(_ volume: MediaVolume) throws -> MediaVolumeScanResult {
        let accessURL = volume.resolvedAccessURL()
        guard FileManager.default.fileExists(atPath: accessURL.path) else {
            throw MediaVolumeError.volumeRemoved(volume.name)
        }
        let hasScope = accessURL.startAccessingSecurityScopedResource()
        guard hasScope || FileManager.default.isReadableFile(atPath: accessURL.path) else {
            throw MediaVolumeError.permissionDenied(volume.name)
        }
        defer { if hasScope { accessURL.stopAccessingSecurityScopedResource() } }
        guard let enumerator = FileManager.default.enumerator(
            at: accessURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else {
            throw MediaVolumeError.unreadable(volume.name)
        }

        var files: [MediaVolumeFile] = []
        var warnings: [String] = []
        while let candidate = enumerator.nextObject() as? URL {
            guard !Task.isCancelled else { break }
            guard let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true, supports(candidate) else { continue }
            guard FileManager.default.isReadableFile(atPath: candidate.path) else {
                warnings.append("Skipped unreadable image “\(candidate.lastPathComponent)”.")
                continue
            }
            guard let source = CGImageSourceCreateWithURL(candidate as CFURL, nil),
                  CGImageSourceGetCount(source) > 0 else {
                warnings.append("Skipped unsupported or damaged image “\(candidate.lastPathComponent)”.")
                continue
            }
            if !ImageDecoder.rawExtensions.contains(candidate.pathExtension.lowercased()),
               (try? ImageDecoder.prepareStandard(from: candidate)) == nil {
                warnings.append("Skipped unsupported or damaged image “\(candidate.lastPathComponent)”.")
                continue
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            files.append(MediaVolumeFile(
                url: candidate,
                orientation: orientation,
                metadata: ImageMetadata.read(from: candidate)
            ))
        }
        files.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        return MediaVolumeScanResult(files: files, warnings: warnings)
    }

    /// The same UTI-derived admission rule is used for discovery and scan. The extension fallback
    /// is needed for RAW formats whose filesystem UTI is not registered by an inserted card.
    static func supports(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ImageDecoder.supportedExtensions.contains(ext) else { return false }
        guard let type = UTType(filenameExtension: ext) else { return true }
        return ImageDecoder.supportedTypes.contains { type.conforms(to: $0) || $0.conforms(to: type) }
            || ImageDecoder.rawExtensions.contains(ext)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
