import Foundation
import Combine

/// Manages discovered and explicitly imported LUT files, scanning and grouping by subfolder.
@MainActor
final class LUTLibrary: ObservableObject {

    struct Category: Identifiable, Sendable {
        let id: String      // category name
        let name: String
        let luts: [CubeLUT]
        let source: LUTSource

        init(id: String, name: String, luts: [CubeLUT], source: LUTSource = .user) {
            self.id = id
            self.name = name
            self.luts = luts
            self.source = source
        }
    }

    @Published var categories: [Category] = []
    @Published var allLUTs: [CubeLUT] = []
    @Published var folderURL: URL?
    @Published var scanError: String?
    /// True while a folder scan is running. Drives the sidebar's progress hint.
    @Published var isScanning: Bool = false
    /// True while one or more explicitly imported files are being parsed.
    @Published var isImporting: Bool = false

    /// Import failures are kept separate from folder-scan failures so one malformed external file
    /// does not blank a healthy Look folder.
    @Published var importError: String?

    /// Fired after every scan publishes its results, whatever started it.
    ///
    /// Exists so `AppViewModel` can drop the engine's cube-filter cache. A `LUTID` is a file path, so
    /// a `.cube` replaced in place keeps its identity and a cached filter would go on serving the old
    /// contents — reachable as of Step 9, when saving a second derive over the same path became a
    /// thing the UI can do.
    ///
    /// A closure rather than a call at each scan site because it covers *every* scan — `setFolder`,
    /// `restoreFolder`, and the rescan after a save — instead of relying on the next person to
    /// remember. The library stays ignorant of the renderer, which is why this is a closure the owner
    /// wires rather than an engine reference held here.
    var onScanned: (() -> Void)?
    /// Fired after a valid external file has joined the canonical Look browser.
    var onImported: ((CubeLUT) -> Void)?
    /// Fired when an explicit import cannot be read or parsed.
    var onImportError: ((String) -> Void)?

    /// Non-fatal diagnostics from the bundled starter resource loader. A damaged starter entry is
    /// omitted, but these diagnostics never replace a healthy user library.
    @Published private(set) var bundledLoadWarnings: [String]

    /// The acknowledgement text shown in the Look inspector and sourced from the bundled manifest.
    let bundledAcknowledgement: String

    private static let settingsKey = "lutFolderBookmark"
    private static let importedBookmarksKey = "lumo.importedLUTBookmarks"

    /// Folder whose security scope we hold open, so it can be released when we
    /// move to a different folder or the library goes away.
    private var scopedURL: URL?
    private var scanTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var scannedCategories: [Category] = []
    private let bundledCategories: [Category]
    private var importedSourceURLs: [URL] = []
    private var importedLUTs: [CubeLUT] = []
    private var importedScopedURLs: [URL] = []

    /// The app-owned home for user-created/imported Looks. A user-selected folder may still be
    /// browsed through `setFolder`, but saved Looks have one stable destination supplied here.
    let userLookFolderURL: URL
    /// Explicit product-facing spelling for callers that need the canonical storage location.
    var canonicalUserLookFolderURL: URL { userLookFolderURL }
    private let preferences: UserDefaults

    init(
        preferences: UserDefaults = .standard,
        userLookFolderURL: URL? = nil,
        includeBundled: Bool = false
    ) {
        self.preferences = preferences
        self.userLookFolderURL = userLookFolderURL ?? LumoSettings.defaultUserLookFolderURL()
        let bundled = includeBundled ? BundledLookLibrary.load() : nil
        self.bundledCategories = bundled?.categories ?? []
        self.bundledLoadWarnings = bundled?.warnings ?? []
        self.bundledAcknowledgement = bundled?.manifest.acknowledgement ?? ""
        restoreImportedLUTs()
        publishCategories()
    }

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
        for url in importedScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Folder management

    func setFolder(_ url: URL) {
        saveBookmark(for: url)
        self.folderURL = url
        scan(url)
    }

    func restoreFolder() {
        guard let data = preferences.data(forKey: Self.settingsKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = url

        // A stale bookmark still resolves once, but won't next launch unless we
        // mint a fresh one now that we hold access.
        if isStale { saveBookmark(for: url) }

        self.folderURL = url
        scan(url)
    }

    private func saveBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            preferences.set(bookmark, forKey: Self.settingsKey)
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    // MARK: - Scanning

    /// Scan `folder` for supported LUT files **off the main actor**, then publish the
    /// finished categories. A 33³ LUT is ~36k lines of text to parse, so a
    /// folder of a few dozen looks would otherwise stall the window at launch.
    func scan(_ folder: URL) {
        scanTask?.cancel()
        scanError = nil
        isScanning = true

        scanTask = Task {
            var interval = LumoSignpostInterval(
                .scan,
                context: LumoTraceContext(sourceFingerprint: folder.standardizedFileURL.path, quality: "background")
            )
            defer { interval.end() }
            let outcome = await Task.detached { Self.scanSync(folder) }.value
            guard !Task.isCancelled else { return }

            self.isScanning = false
            switch outcome {
            case .failure(let message):
                self.scanError = message
                self.scannedCategories = []
            case .success(let cats):
                self.scanError = nil
                self.scannedCategories = cats
            }
            self.publishCategories()
            // After publishing, and on the failure path too: a scan that found nothing still means
            // the folder changed under whatever the engine has cached.
            self.onScanned?()
        }
    }

    // MARK: - External file import

    /// Add a `.cube` or text-based `.look` from any user-selected file location to the canonical
    /// Look browser. The original path is retained, rather than copying the table into an app-owned
    /// file, so a persisted `LUTID` continues to identify the same resource and an explicit refresh
    /// can observe a file replacement.
    func importLUT(from url: URL, audition: Bool = true) {
        guard CubeLUT.supportedFileExtensions.contains(url.pathExtension.lowercased()) else {
            reportImportError("Unsupported LUT file type “\(url.pathExtension)”")
            return
        }

        if !importedSourceURLs.contains(where: { Self.canonicalPath($0) == Self.canonicalPath(url) }) {
            importedSourceURLs.append(url)
            persistImportedBookmarks()
        }
        retainSecurityScope(for: url)

        importTask?.cancel()
        isImporting = true
        importError = nil
        let sources = importedSourceURLs
        importTask = Task {
            let imported = await Task.detached {
                sources.compactMap { source -> CubeLUT? in
                    try? CubeLUT(url: source, category: "Imported")
                }
            }.value
            guard !Task.isCancelled else { return }

            self.isImporting = false
            self.importedLUTs = imported
            self.publishCategories()

            // The callback is intentionally before cache invalidation: AppViewModel selects the new
            // value, then the normal library-change path flushes any filter for the same stable path.
            if let added = imported.first(where: { Self.canonicalPath($0.url) == Self.canonicalPath(url) }) {
                if audition { self.onImported?(added) }
            } else {
                let detail: String
                do {
                    _ = try CubeLUT(url: url, category: "Imported")
                    detail = "the file was not retained"
                } catch {
                    detail = error.localizedDescription
                }
                self.reportImportError("Could not import “\(url.lastPathComponent)”: \(detail)")
            }
            self.onScanned?()
        }
    }

    /// Re-read explicitly imported resources and the configured folder. This is the safe refresh
    /// boundary for an editor that has an external file replaced in place: it publishes a new table
    /// with the same stable path ID, then asks the renderer to evict its old GPU filter.
    func refresh() {
        reloadImportedLUTs()
        if let folderURL { scan(folderURL) }
    }

    private func reloadImportedLUTs() {
        guard !importedSourceURLs.isEmpty else { return }
        importTask?.cancel()
        isImporting = true
        let sources = importedSourceURLs
        importTask = Task {
            let imported = await Task.detached {
                sources.compactMap { try? CubeLUT(url: $0, category: "Imported") }
            }.value
            guard !Task.isCancelled else { return }
            self.isImporting = false
            self.importedLUTs = imported
            self.publishCategories()
            self.onScanned?()
        }
    }

    private func reportImportError(_ message: String) {
        importError = message
        onImportError?(message)
    }

    private func publishCategories() {
        var byCategory: [String: (name: String, source: LUTSource, luts: [CubeLUT])] = [:]
        for category in bundledCategories + scannedCategories {
            let key = "\(category.source.rawValue):\(category.name)"
            byCategory[key, default: (category.name, category.source, [])].luts.append(contentsOf: category.luts)
        }
        for lut in importedLUTs {
            // An imported file can also live inside the selected folder. One stable ID must produce
            // one browser row, not two rows whose selection would be indistinguishable.
            if !byCategory.values.contains(where: { $0.luts.contains(where: { $0.lutID == lut.lutID }) }) {
                byCategory["user:Imported", default: ("Imported", .user, [])].luts.append(lut)
            }
        }

        categories = byCategory.keys.sorted { lhs, rhs in
            let left = byCategory[lhs]!
            let right = byCategory[rhs]!
            if left.source != right.source { return left.source == .bundled }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }.compactMap { key in
            guard let group = byCategory[key] else { return nil }
            let luts = group.luts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return luts.isEmpty ? nil : Category(
                id: key,
                name: group.name,
                luts: luts,
                source: group.source
            )
        }
        allLUTs = categories.flatMap(\.luts)
    }

    private func retainSecurityScope(for url: URL) {
        guard !importedScopedURLs.contains(where: { Self.canonicalPath($0) == Self.canonicalPath(url) }),
              url.startAccessingSecurityScopedResource()
        else { return }
        importedScopedURLs.append(url)
    }

    private func restoreImportedLUTs() {
        guard let records = preferences.array(forKey: Self.importedBookmarksKey) as? [Data] else {
            return
        }
        for data in records {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            retainSecurityScope(for: url)
            if isStale { persistImportedBookmarks() }
            if !importedSourceURLs.contains(where: { Self.canonicalPath($0) == Self.canonicalPath(url) }) {
                importedSourceURLs.append(url)
            }
        }
        reloadImportedLUTs()
    }

    private func persistImportedBookmarks() {
        let bookmarks = importedSourceURLs.compactMap { url -> Data? in
            try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        preferences.set(bookmarks, forKey: Self.importedBookmarksKey)
    }

    private enum ScanOutcome {
        case success([Category])
        case failure(String)
    }

    /// The blocking half of `scan`. Pure: takes a folder, returns categories.
    /// `nonisolated` so it can run on a background executor.
    private nonisolated static func scanSync(_ folder: URL) -> ScanOutcome {
        var categoryMap: [String: [CubeLUT]] = [:]

        // `enumerator(at:)` hands back a live-but-empty enumerator for a folder
        // that has been moved or deleted, so a nil check alone would report
        // "no LUTs" for what is really a missing folder — the most likely
        // failure, since the folder is restored from a bookmark each launch.
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure("Can't find “\(folder.lastPathComponent)” — it may have been moved or renamed.")
        }
        guard fm.isReadableFile(atPath: folder.path) else {
            return .failure("No permission to read “\(folder.lastPathComponent)”.")
        }
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .failure("Can't read “\(folder.lastPathComponent)”.")
        }

        // Resolve symlinks on both sides so the category math holds even when
        // the root is itself a symlink (matches ImageCollection.loadFromFolder).
        let rootPath = folder.resolvingSymlinksInPath().path
        var skipped = 0

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { return .success([]) }
            guard CubeLUT.supportedFileExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }

            // Determine category from the path relative to the root.
            let path = fileURL.resolvingSymlinksInPath().path
            let relativePath = path.hasPrefix(rootPath)
                ? String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : fileURL.lastPathComponent
            let components = relativePath.split(separator: "/")
            let category = components.count > 1 ? String(components[0]) : "General"

            do {
                let lut = try CubeLUT(url: fileURL, category: category, source: .user)
                categoryMap[category, default: []].append(lut)
            } catch {
                skipped += 1
                print("Skipping \(fileURL.lastPathComponent): \(error)")
            }
        }

        var cats: [Category] = []
        for key in categoryMap.keys.sorted() {
            let sorted = categoryMap[key]!.sorted { $0.name < $1.name }
            cats.append(Category(id: key, name: key, luts: sorted))
        }

        if cats.isEmpty {
            return .failure(skipped > 0
                ? "No readable .cube files (or text-based .look files) in “\(folder.lastPathComponent)” (\(skipped) could not be parsed)."
                : "No .cube files (or text-based .look files) in “\(folder.lastPathComponent)”.")
        }
        return .success(cats)
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
