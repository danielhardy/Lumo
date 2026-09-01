import Foundation

/// The source information persisted alongside an edit document.
///
/// A path is useful for the common case and for diagnostics. The bookmark is what makes a file
/// relocatable inside the user's source folder; the store never writes beside the original image.
struct EditSourceReference: Codable, Sendable, Equatable {
    let assetID: PhotoAssetID
    let url: URL?

    init(assetID: PhotoAssetID, url: URL? = nil) {
        self.assetID = assetID
        self.url = url
    }
}

/// The result of looking up one source in the edit store.
struct EditDocumentLoadResult: Sendable, Equatable {
    let document: EditDocument
    let found: Bool
    let status: EditDocumentStore.Status
}

/// Durable per-photo edit records.
///
/// The representation is intentionally a single JSON envelope rather than a database. An edit is a
/// small value (currently a RAW settings struct, an adjustment array, and a LUT reference), and the
/// catalog is expected to be far smaller than a Lightroom-scale library. A dictionary keyed by the
/// stable `PhotoAssetID` keeps lookup simple; each value adds the canonical path and a security-scoped
/// bookmark for relinking.
///
/// The primary file is replaced with `Data.write(options: .atomic)`. Before replacing it, a valid
/// primary payload is copied atomically to `.bak`. A failed or interrupted replacement therefore
/// leaves the previous primary intact, and a malformed primary can be recovered from the backup.
/// All file work is performed inside this actor, so callers on `@MainActor` only await values.
actor EditDocumentStore {

    static let currentVersion = 1

    enum Status: Sendable, Equatable {
        case notLoaded
        case empty
        case ready
        case migrated(from: Int)
        case relinked
        case recoveredFromBackup
        case corrupt(String)
        case writeFailure(String)
        case unsupportedVersion(Int)

        var message: String? {
            switch self {
            case .notLoaded, .empty, .ready:
                return nil
            case .migrated(let version):
                return "Migrated edit records from schema \(version)."
            case .relinked:
                return "Restored edits after the source photo moved."
            case .recoveredFromBackup:
                return "Edit records were damaged; restored the last known-good copy."
            case .corrupt(let detail):
                return "Could not read edit records (\(detail)); using neutral edits until the store is repaired."
            case .writeFailure(let detail):
                return "Could not save edit records: \(detail)"
            case .unsupportedVersion(let version):
                return "Edit records use newer schema \(version); update Lumo before saving edits."
            }
        }

        var isActionable: Bool {
            switch self {
            case .notLoaded, .empty, .ready:
                return false
            case .migrated, .relinked, .recoveredFromBackup, .corrupt, .writeFailure, .unsupportedVersion:
                return true
            }
        }
    }

    enum StoreError: Error, LocalizedError, Equatable {
        case cannotWrite(String)
        case newerSchema(Int)

        var errorDescription: String? {
            switch self {
            case .cannotWrite(let detail): return detail
            case .newerSchema(let version):
                return "Edit records use newer schema \(version); update Lumo before saving edits."
            }
        }
    }

    private struct SourceLocator: Codable, Sendable, Equatable {
        var path: String?
        var fileName: String?
        var bookmarkData: Data?
    }

    private struct Record: Codable, Sendable, Equatable {
        var document: EditDocument
        var source: SourceLocator
    }

    private struct Envelope: Codable, Sendable, Equatable {
        var schemaVersion: Int
        var records: [String: Record]
    }

    /// The first prototype wrote a bare map of `PhotoAssetID` to `EditDocument`. Keep that shape
    /// readable as schema 0, and always write the envelope above afterwards. A versionless envelope
    /// is also accepted so a future migration can be added without weakening the current schema.
    private struct VersionlessEnvelope: Codable {
        var records: [String: Record]
    }

    private let fileURL: URL
    private let backupURL: URL
    private var records: [String: Record] = [:]
    private var hasLoaded = false
    private var writesBlockedByNewerSchema = false
    private(set) var status: Status = .notLoaded
    /// Testable evidence that persistence work ran on the actor executor, not the main actor.
    private(set) var lastIOWasMainThread = false

    init(fileURL: URL = EditDocumentStore.defaultFileURL, backupURL: URL? = nil) {
        self.fileURL = fileURL
        self.backupURL = backupURL ?? fileURL.appendingPathExtension("bak")
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Lumo", isDirectory: true)
            .appendingPathComponent("edit-records.json")
    }

    /// Load the document for a source. A missing record is the normal first-open case and returns
    /// the identity document; a damaged catalog never turns into a fabricated edit.
    func load(for source: EditSourceReference) -> EditDocumentLoadResult {
        ensureLoaded()

        let key = source.assetID.description
        if let record = records[key] {
            // Resource-backed IDs intentionally survive a move, so direct lookup is normally
            // enough. Still refresh the locator and surface the move when the canonical path has
            // changed; this keeps relink observable even on volumes with stable resource IDs.
            if let url = source.url, record.source.path != url.standardizedFileURL.resolvingSymlinksInPath().path {
                records[key] = Record(document: record.document, source: makeLocator(for: url))
                let previousStatus = status
                status = .relinked
                do {
                    try persist()
                } catch {
                    status = .writeFailure(error.localizedDescription)
                }
                if previousStatus.isActionable, case .writeFailure = status {} else if previousStatus.isActionable {
                    status = previousStatus
                }
            }
            return EditDocumentLoadResult(document: record.document, found: true, status: status)
        }

        guard let url = source.url,
              let (oldKey, record) = records.first(where: { matches($0.value.source, url: url) }) else {
            return EditDocumentLoadResult(document: EditDocument(), found: false, status: status)
        }

        // The bookmark found the same photo at a new path. Move the record to the new stable key,
        // then write the new locator so a second relaunch does not need another relink pass.
        records[key] = Record(document: record.document, source: makeLocator(for: url))
        records.removeValue(forKey: oldKey)
        let previousStatus = status
        status = .relinked
        do {
            try persist()
        } catch {
            status = .writeFailure(error.localizedDescription)
        }
        if previousStatus.isActionable, case .writeFailure = status {} else if previousStatus.isActionable {
            status = previousStatus
        }
        return EditDocumentLoadResult(document: record.document, found: true, status: status)
    }

    /// Convenience lookup for callers that only have an ID. Without a URL there is no relink pass.
    func load(for assetID: PhotoAssetID) -> EditDocumentLoadResult {
        load(for: EditSourceReference(assetID: assetID))
    }

    func document(for source: EditSourceReference) -> EditDocument? {
        let result = load(for: source)
        return result.found ? result.document : nil
    }

    /// Save a document and its source locator. The operation is serialized by the actor and never
    /// modifies the source file. Identity documents are retained too, so clearing an existing edit
    /// survives relaunch rather than resurrecting the old record.
    func save(_ document: EditDocument, for source: EditSourceReference) throws {
        ensureLoaded()
        guard !writesBlockedByNewerSchema else {
            if case .unsupportedVersion(let version) = status { throw StoreError.newerSchema(version) }
            throw StoreError.newerSchema(EditDocumentStore.currentVersion + 1)
        }

        records[source.assetID.description] = Record(
            document: document,
            source: makeLocator(for: source.url)
        )
        do {
            try persist()
            status = .ready
        } catch {
            status = .writeFailure(error.localizedDescription)
            throw error
        }
    }

    func save(_ document: EditDocument, for assetID: PhotoAssetID, url: URL? = nil) throws {
        try save(document, for: EditSourceReference(assetID: assetID, url: url))
    }

    // MARK: - Loading and migration

    private func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        lastIOWasMainThread = Thread.isMainThread

        let primary = read(fileURL)
        switch primary {
        case .success(let decoded):
            install(decoded)
        case .failure(let primaryError):
            let backup = read(backupURL)
            switch backup {
            case .success(let decoded):
                install(decoded)
                status = .recoveredFromBackup
            case .failure(let backupError):
                if case .unsupported(let version) = primaryError {
                    writesBlockedByNewerSchema = true
                    status = .unsupportedVersion(version)
                } else if case .missing = primaryError, case .missing = backupError {
                    records = [:]
                    status = .empty
                } else {
                    records = [:]
                    status = .corrupt("\(primaryError.summary); backup: \(backupError.summary)")
                }
            }
        }
    }

    private enum ReadFailure: Error {
        case missing
        case malformed(String)
        case unsupported(Int)

        var summary: String {
            switch self {
            case .missing: return "store is missing"
            case .malformed(let detail): return detail
            case .unsupported(let version): return "schema \(version) is newer than this build"
            }
        }
    }

    private struct DecodedFile {
        let envelope: Envelope
        let migratedFrom: Int?
    }

    private func read(_ url: URL) -> Result<DecodedFile, ReadFailure> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.missing) }
        do {
            let data = try Data(contentsOf: url)
            do {
                let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                guard envelope.schemaVersion <= Self.currentVersion else {
                    return .failure(.unsupported(envelope.schemaVersion))
                }
                return .success(DecodedFile(envelope: envelope, migratedFrom: nil))
            } catch {
                if let versionless = try? JSONDecoder().decode(VersionlessEnvelope.self, from: data) {
                    return .success(DecodedFile(
                        envelope: Envelope(schemaVersion: Self.currentVersion, records: versionless.records),
                        migratedFrom: 0
                    ))
                }

                if let legacy = try? JSONDecoder().decode([String: EditDocument].self, from: data) {
                    let records = legacy.mapValues { document in
                        Record(
                            document: document,
                            source: SourceLocator(path: nil, fileName: nil, bookmarkData: nil)
                        )
                    }
                    return .success(DecodedFile(
                        envelope: Envelope(schemaVersion: Self.currentVersion, records: records),
                        migratedFrom: 0
                    ))
                }
                return .failure(.malformed(error.localizedDescription))
            }
        } catch {
            return .failure(.malformed(error.localizedDescription))
        }
    }

    private func install(_ decoded: DecodedFile) {
        records = decoded.envelope.records
        status = decoded.migratedFrom.map(Status.migrated) ?? .ready
    }

    // MARK: - Atomic writes and relinking

    private func persist() throws {
        lastIOWasMainThread = Thread.isMainThread
        let data: Data
        do {
            data = try JSONEncoder().encode(Envelope(schemaVersion: Self.currentVersion, records: records))
        } catch {
            throw StoreError.cannotWrite("could not encode records: \(error.localizedDescription)")
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Never copy a malformed or newer primary into the recovery slot. If the new primary
            // write is interrupted, the old primary or the previous valid backup remains usable.
            if let oldData = try? Data(contentsOf: fileURL), case .success = read(fileURL) {
                try oldData.write(to: backupURL, options: .atomic)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw StoreError.cannotWrite(error.localizedDescription)
        }
    }

    private func makeLocator(for url: URL?) -> SourceLocator {
        guard let url else { return SourceLocator(path: nil, fileName: nil, bookmarkData: nil) }
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let bookmark = (try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? (try? url.bookmarkData())
        return SourceLocator(path: canonical.path, fileName: canonical.lastPathComponent, bookmarkData: bookmark)
    }

    private func matches(_ locator: SourceLocator, url: URL) -> Bool {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        if locator.path == canonical.path { return true }

        guard let bookmarkData = locator.bookmarkData else { return false }
        var stale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return false }
        return resolved.standardizedFileURL.resolvingSymlinksInPath() == canonical
    }
}
