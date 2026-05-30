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

    private static let settingsKey = "lutFolderBookmark"

    // MARK: - Folder management

    func setFolder(_ url: URL) {
        // Create a security-scoped bookmark for persistence
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
        self.folderURL = url
        scan(url)
    }

    // MARK: - Scanning

    func scan(_ folder: URL) {
        scanError = nil
        var categoryMap: [String: [CubeLUT]] = [:]

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            scanError = "Cannot read folder"
            return
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "cube" else { continue }

            // Determine category from relative path
            let relativePath = fileURL.path.replacingOccurrences(of: folder.path + "/", with: "")
            let components = relativePath.split(separator: "/")
            let category = components.count > 1 ? String(components[0]) : "General"

            do {
                let lut = try CubeLUT(url: fileURL, category: category)
                categoryMap[category, default: []].append(lut)
            } catch {
                print("Skipping \(fileURL.lastPathComponent): \(error)")
            }
        }

        // Sort
        var cats: [Category] = []
        for key in categoryMap.keys.sorted() {
            let sorted = categoryMap[key]!.sorted { $0.name < $1.name }
            cats.append(Category(id: key, name: key, luts: sorted))
        }

        self.categories = cats
        self.allLUTs = cats.flatMap(\.luts)
    }
}
