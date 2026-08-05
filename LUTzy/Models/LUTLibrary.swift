import Foundation
import Combine

/// Manages a folder of .cube LUT files, scanning and grouping by subfolder.
@MainActor
final class LUTLibrary: ObservableObject {

    struct Category: Identifiable {
        let id: String      // category name
        let name: String
        let luts: [CubeLUT]
    }

    @Published var categories: [Category] = []
    @Published var allLUTs: [CubeLUT] = []
    @Published var folderURL: URL?
    @Published var scanError: String?
    /// True while a folder scan is running. Drives the sidebar's progress hint.
    @Published var isScanning: Bool = false

    private static let settingsKey = "lutFolderBookmark"

    /// Folder whose security scope we hold open, so it can be released when we
    /// move to a different folder or the library goes away.
    private var scopedURL: URL?
    private var scanTask: Task<Void, Never>?

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Folder management

    func setFolder(_ url: URL) {
        saveBookmark(for: url)
        self.folderURL = url
        scan(url)
    }

    func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey) else { return }
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
            UserDefaults.standard.set(bookmark, forKey: Self.settingsKey)
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    // MARK: - Scanning

    /// Scan `folder` for .cube files **off the main actor**, then publish the
    /// finished categories. A 33³ LUT is ~36k lines of text to parse, so a
    /// folder of a few dozen looks would otherwise stall the window at launch.
    func scan(_ folder: URL) {
        scanTask?.cancel()
        scanError = nil
        isScanning = true

        scanTask = Task {
            let outcome = await Task.detached { Self.scanSync(folder) }.value
            guard !Task.isCancelled else { return }

            self.isScanning = false
            switch outcome {
            case .failure(let message):
                self.scanError = message
                self.categories = []
                self.allLUTs = []
            case .success(let cats):
                self.scanError = nil
                self.categories = cats
                self.allLUTs = cats.flatMap(\.luts)
            }
        }
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
            guard fileURL.pathExtension.lowercased() == "cube" else { continue }

            // Determine category from the path relative to the root.
            let path = fileURL.resolvingSymlinksInPath().path
            let relativePath = path.hasPrefix(rootPath)
                ? String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : fileURL.lastPathComponent
            let components = relativePath.split(separator: "/")
            let category = components.count > 1 ? String(components[0]) : "General"

            do {
                let lut = try CubeLUT(url: fileURL, category: category)
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
                ? "No readable .cube files in “\(folder.lastPathComponent)” (\(skipped) could not be parsed)."
                : "No .cube files in “\(folder.lastPathComponent)”.")
        }
        return .success(cats)
    }
}
