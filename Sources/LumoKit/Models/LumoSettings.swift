import Foundation
import AppKit
import Combine

/// The two folder defaults that affect operations started after the setting changes.
public enum LumoFolderKind: String, CaseIterable, Codable, Sendable {
    case source
    case export

    public var title: String {
        switch self {
        case .source: return "Default Source / Import Folder"
        case .export: return "Default Export Folder"
        }
    }

    var legacyKey: String {
        switch self {
        case .source: return "Lumo.defaultSourceFolderBookmark"
        case .export: return "Lumo.defaultExportFolderBookmark"
        }
    }
}

/// A deliberately small status model for Settings and for panel-free tests. The bookmark remains
/// stored when a folder becomes unavailable, so the user can recover it without losing a preference.
public enum LumoFolderAvailability: String, Codable, Sendable, Equatable {
    case notConfigured
    case available
    case unavailable
    case inaccessible
}

public struct LumoFolderStatus: Sendable, Equatable {
    public let kind: LumoFolderKind
    public let availability: LumoFolderAvailability
    public let displayName: String?
    public let url: URL?

    public var isConfigured: Bool { availability != .notConfigured }
    public var isAvailable: Bool { availability == .available }

    static func notConfigured(_ kind: LumoFolderKind) -> Self {
        Self(kind: kind, availability: .notConfigured, displayName: nil, url: nil)
    }
}

public struct LumoFolderTestResult: Sendable, Equatable {
    public let status: LumoFolderStatus
    public let message: String

    public var isUsable: Bool { status.isAvailable }
}

/// Persistent application preferences. Values use namespaced UserDefaults keys and a schema version;
/// workflow-owned bookmarks and unrelated settings are never replaced by a settings write.
@MainActor
public final class LumoSettings: ObservableObject {
    public static let currentSchemaVersion = 1

    private enum Key {
        static let schemaVersion = "Lumo.settings.schemaVersion"
        static let alwaysDarkMode = "Lumo.settings.alwaysDarkMode"
        static let sourceFolder = "Lumo.settings.defaultSourceFolder"
        static let exportFolder = "Lumo.settings.defaultExportFolder"
        static let legacyDarkMode = "Lumo.alwaysDarkMode"
    }

    private struct PersistedFolder: Codable, Equatable {
        let bookmarkData: Data
        let displayName: String
        let pathHint: String
    }

    @Published public var alwaysDarkMode: Bool {
        didSet {
            guard alwaysDarkMode != oldValue else { return }
            preferences.set(alwaysDarkMode, forKey: Key.alwaysDarkMode)
        }
    }

    @Published public private(set) var sourceFolderStatus: LumoFolderStatus
    @Published public private(set) var exportFolderStatus: LumoFolderStatus

    /// The app-owned location for user-created and imported Looks. Bundled Looks, if added later,
    /// remain a separate resource and are never mixed into this directory.
    public let userLookFolderURL: URL
    public var canonicalUserLookFolderURL: URL { userLookFolderURL }

    private let preferences: UserDefaults
    private let fileManager: FileManager
    private var records: [LumoFolderKind: PersistedFolder] = [:]
    private var retainedURLs: [LumoFolderKind: URL] = [:]

    public convenience init() {
        self.init(preferences: .standard)
    }

    init(
        preferences: UserDefaults = .standard,
        userLookFolderURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.preferences = preferences
        self.fileManager = fileManager
        self.userLookFolderURL = userLookFolderURL ?? Self.defaultUserLookFolderURL(fileManager: fileManager)
        self.alwaysDarkMode = preferences.object(forKey: Key.alwaysDarkMode) as? Bool ?? false
        self.sourceFolderStatus = .notConfigured(.source)
        self.exportFolderStatus = .notConfigured(.export)

        migrateIfNeeded()
        // Migration may have supplied the appearance value.
        self.alwaysDarkMode = preferences.object(forKey: Key.alwaysDarkMode) as? Bool ?? false
        loadRecords()
        refreshFolderStatus()
    }

    deinit {
        for url in retainedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    public static func defaultUserLookFolderURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Lumo", isDirectory: true)
            .appendingPathComponent("Looks", isDirectory: true)
    }

    public var defaultSourceFolderURL: URL? { sourceFolderStatus.url }
    public var defaultExportFolderURL: URL? { exportFolderStatus.url }

    public func status(for kind: LumoFolderKind) -> LumoFolderStatus {
        kind == .source ? sourceFolderStatus : exportFolderStatus
    }

    /// Save a user-selected folder as a security-scoped bookmark. This is the panel-independent seam
    /// used by Settings tests; the Settings view owns the AppKit folder panel itself.
    @discardableResult
    public func setDefaultFolder(_ url: URL, for kind: LumoFolderKind) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            records[kind] = PersistedFolder(
                bookmarkData: bookmark,
                displayName: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                pathHint: url.path
            )
            persist(record: records[kind], for: kind)
            let retained = retainAccess(to: url, for: kind)
            let usable = retained
                && (kind == .source
                    ? fileManager.isReadableFile(atPath: url.path)
                    : fileManager.isWritableFile(atPath: url.path))
            updateStatus(for: kind, availability: usable ? .available : .inaccessible, url: usable ? url : nil)
            return usable
        } catch {
            return false
        }
    }

    public func resetDefaultFolder(_ kind: LumoFolderKind) {
        if let url = retainedURLs.removeValue(forKey: kind) {
            url.stopAccessingSecurityScopedResource()
        }
        records.removeValue(forKey: kind)
        preferences.removeObject(forKey: key(for: kind))
        updateStatus(for: kind, availability: .notConfigured, url: nil)
    }

    /// Re-resolve a bookmark and refresh it only after access succeeds. A failed resolution leaves the
    /// old bytes intact, which is important for a disconnected drive or a later relink.
    public func refreshFolderStatus() {
        for kind in LumoFolderKind.allCases {
            guard let record = records[kind] else {
                updateStatus(for: kind, availability: .notConfigured, url: nil)
                continue
            }
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: record.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                updateStatus(for: kind, availability: .unavailable, url: nil)
                continue
            }

            guard retainAccess(to: url, for: kind) else {
                updateStatus(for: kind, availability: .inaccessible, url: nil)
                continue
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                updateStatus(for: kind, availability: .unavailable, url: nil)
                continue
            }
            let hasRequiredPermission = kind == .source
                ? fileManager.isReadableFile(atPath: url.path)
                : fileManager.isWritableFile(atPath: url.path)
            guard hasRequiredPermission else {
                updateStatus(for: kind, availability: .inaccessible, url: nil)
                continue
            }

            // Only replace a stale record once the resolved resource is usable. The preference is
            // therefore recoverable even if a drive is unavailable during launch.
            if stale, let fresh = try? url.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
            ) {
                let refreshed = PersistedFolder(
                    bookmarkData: fresh, displayName: record.displayName, pathHint: url.path
                )
                records[kind] = refreshed
                persist(record: refreshed, for: kind)
            }
            updateStatus(for: kind, availability: .available, url: url)
        }
    }

    public func testDefaultFolder(_ kind: LumoFolderKind) -> LumoFolderTestResult {
        refreshFolderStatus()
        let current = status(for: kind)
        switch current.availability {
        case .notConfigured:
            return LumoFolderTestResult(status: current, message: "No default folder is configured.")
        case .unavailable:
            return LumoFolderTestResult(
                status: current,
                message: (current.displayName ?? "The configured folder")
                    + " is unavailable. Choose it again to restore access."
            )
        case .inaccessible:
            return LumoFolderTestResult(
                status: current,
                message: "Lumo cannot access " + (current.displayName ?? "the configured folder")
                    + ". Choose it again to grant permission."
            )
        case .available:
            let action = kind == .source ? "read" : "write"
            return LumoFolderTestResult(
                status: current,
                message: "Ready to " + action + " " + (current.displayName ?? "this folder")
                    + " for future operations."
            )
        }
    }

    /// Create the app-owned Look directory when supported. This location is not a user-selected
    /// bookmark, so it does not require security-scoped access.
    @discardableResult
    public func ensureUserLookFolder() -> URL? {
        do {
            try fileManager.createDirectory(at: userLookFolderURL, withIntermediateDirectories: true)
            return fileManager.isWritableFile(atPath: userLookFolderURL.path) ? userLookFolderURL : nil
        } catch {
            return nil
        }
    }

    @discardableResult
    public func revealUserLookFolder() -> Bool {
        guard let folder = ensureUserLookFolder() else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
        return true
    }

    private func migrateIfNeeded() {
        let version = preferences.integer(forKey: Key.schemaVersion)
        guard version < Self.currentSchemaVersion else { return }

        if preferences.object(forKey: Key.alwaysDarkMode) == nil,
           let old = preferences.object(forKey: Key.legacyDarkMode) as? Bool {
            preferences.set(old, forKey: Key.alwaysDarkMode)
        }
        // A previous release's current source/Look bookmarks are safe seeds for the new future
        // operation defaults. The original keys remain untouched for their owning workflows.
        migrateLegacyBookmark("imageSourceFolderBookmark", to: .source)
        for kind in LumoFolderKind.allCases {
            migrateLegacyBookmark(kind.legacyKey, to: kind)
        }
        preferences.set(Self.currentSchemaVersion, forKey: Key.schemaVersion)
    }

    private func migrateLegacyBookmark(_ oldKey: String, to kind: LumoFolderKind) {
        guard preferences.data(forKey: key(for: kind)) == nil,
              let data = preferences.data(forKey: oldKey) else { return }
        var stale = false
        let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale
        )
        let displayName = url?.lastPathComponent ?? "Configured folder"
        let path = url?.path ?? displayName
        let record = PersistedFolder(bookmarkData: data, displayName: displayName, pathHint: path)
        persist(record: record, for: kind)
    }

    private func loadRecords() {
        for kind in LumoFolderKind.allCases {
            guard let data = preferences.data(forKey: key(for: kind)),
                  let record = try? JSONDecoder().decode(PersistedFolder.self, from: data) else { continue }
            records[kind] = record
        }
    }

    private func persist(record: PersistedFolder?, for kind: LumoFolderKind) {
        guard let record, let data = try? JSONEncoder().encode(record) else { return }
        preferences.set(data, forKey: key(for: kind))
    }

    private func key(for kind: LumoFolderKind) -> String {
        kind == .source ? Key.sourceFolder : Key.exportFolder
    }

    @discardableResult
    private func retainAccess(to url: URL, for kind: LumoFolderKind) -> Bool {
        if retainedURLs[kind] == url { return true }
        if let old = retainedURLs.removeValue(forKey: kind) {
            old.stopAccessingSecurityScopedResource()
        }
        guard url.startAccessingSecurityScopedResource() else { return false }
        retainedURLs[kind] = url
        return true
    }

    private func updateStatus(
        for kind: LumoFolderKind,
        availability: LumoFolderAvailability,
        url: URL?
    ) {
        let name = records[kind]?.displayName
        let status = LumoFolderStatus(kind: kind, availability: availability, displayName: name, url: url)
        if kind == .source { sourceFolderStatus = status } else { exportFolderStatus = status }
    }
}
