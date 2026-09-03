import Foundation

/// The provenance record shipped beside each starter Look. Keeping this data in the bundle makes
/// licensing review auditable without relying on a release note or a human-maintained spreadsheet.
struct BundledLookManifest: Codable, Sendable {
    let schemaVersion: Int
    let acknowledgement: String
    let looks: [Entry]

    struct Entry: Codable, Sendable {
        let id: String
        let name: String
        let category: String
        let resource: String
        let sourceAuthor: String
        let source: String
        let license: String
        let attribution: String
        let redistribution: String
        let approval: Approval
    }

    struct Approval: Codable, Sendable {
        let status: String
        let recordID: String
        let reviewer: String
        let approvedAt: String
        let notes: String
    }
}

/// Loads the read-only starter Looks from the package resource bundle.
///
/// Runtime loading is deliberately tolerant at the individual-entry boundary: a damaged resource
/// is reported and skipped while healthy user or bundled Looks remain usable. `validate(bundle:)`
/// is the strict build/release gate and rejects the complete package when any provenance or asset
/// record is incomplete.
struct BundledLookLibrary: Sendable {
    let manifest: BundledLookManifest
    let looks: [CubeLUT]
    let warnings: [String]

    var categories: [LUTLibrary.Category] {
        let grouped = Dictionary(grouping: looks, by: \.category)
        return grouped.keys.sorted().map { category in
            LUTLibrary.Category(
                id: "bundled:\(category)",
                name: category,
                luts: grouped[category, default: []].sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                },
                source: .bundled
            )
        }
    }

    static let resourceSubdirectory = "StarterLooks"
    static let manifestName = "manifest"

    /// Load whatever valid bundled entries are available. This is the runtime partial-failure path.
    static func load(bundle: Bundle = .module) -> Self {
        do {
            let manifest = try readManifest(from: bundle)
            guard let manifestURL = bundle.url(
                forResource: manifestName,
                withExtension: "json",
                subdirectory: resourceSubdirectory
            ) else {
                throw ValidationError.missingResource("\(resourceSubdirectory)/manifest.json")
            }
            return load(manifest: manifest, resourceDirectory: manifestURL.deletingLastPathComponent())
        } catch {
            return Self(
                manifest: BundledLookManifest(
                    schemaVersion: 0,
                    acknowledgement: "Starter Look metadata is unavailable.",
                    looks: []
                ),
                looks: [],
                warnings: ["Starter Looks could not be loaded: \(error.localizedDescription)"]
            )
        }
    }

    /// Runtime loader seam used to exercise partial-library behavior without modifying packaged
    /// resources. It is also useful to release tooling that stages a bundle before final signing.
    static func load(
        manifest: BundledLookManifest,
        resourceDirectory: URL
    ) -> Self {
        var looks: [CubeLUT] = []
        var warnings: [String] = []
        var seenIDs = Set<String>()

        for entry in manifest.looks {
            do {
                try validateProvenance(entry)
                guard isSafeRelativePath(entry.resource) else {
                    throw ValidationError.invalid("unsafe resource path \(entry.resource)")
                }
                let resourceURL = resourceDirectory.appendingPathComponent(entry.resource)
                guard FileManager.default.fileExists(atPath: resourceURL.path) else {
                    throw ValidationError.missingResource(entry.resource)
                }
                let lut = try CubeLUT(
                    url: resourceURL,
                    category: entry.category,
                    source: .bundled,
                    displayName: entry.name
                )
                guard seenIDs.insert(lut.id).inserted else {
                    throw ValidationError.duplicate("resource identity \(lut.id)")
                }
                looks.append(lut)
            } catch {
                warnings.append("Starter Look “\(entry.name)” was skipped: \(error.localizedDescription)")
            }
        }

        return Self(manifest: manifest, looks: looks, warnings: warnings)
    }

    /// Strict package/release validation. Every manifest entry must have complete provenance and a
    /// valid included 3D LUT; one bad entry fails the gate rather than shipping an unreviewed asset.
    static func validate(bundle: Bundle = .module) throws -> BundledLookManifest {
        let manifest = try readManifest(from: bundle)
        guard manifest.schemaVersion == 1 else {
            throw ValidationError.invalid("unsupported manifest schema \(manifest.schemaVersion)")
        }
        guard !manifest.acknowledgement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalid("user acknowledgement is missing")
        }

        var ids = Set<String>()
        var resources = Set<String>()
        for entry in manifest.looks {
            try validate(entry: entry, bundle: bundle, ids: &ids, resources: &resources)
        }
        return manifest
    }

    private static func readManifest(from bundle: Bundle) throws -> BundledLookManifest {
        guard let url = bundle.url(
            forResource: manifestName,
            withExtension: "json",
            subdirectory: resourceSubdirectory
        ) else {
            throw ValidationError.missingResource("\(resourceSubdirectory)/manifest.json")
        }
        do {
            return try JSONDecoder().decode(BundledLookManifest.self, from: Data(contentsOf: url))
        } catch {
            throw ValidationError.invalid("manifest.json is not valid JSON: \(error.localizedDescription)")
        }
    }

    private static func resourceURL(
        for entry: BundledLookManifest.Entry,
        bundle: Bundle
    ) -> URL? {
        guard isSafeRelativePath(entry.resource) else { return nil }
        let resource = (entry.resource as NSString)
        return bundle.url(
            forResource: resource.deletingPathExtension,
            withExtension: resource.pathExtension,
            subdirectory: resourceSubdirectory
        )
    }

    private static func validate(
        entry: BundledLookManifest.Entry,
        bundle: Bundle,
        ids: inout Set<String>,
        resources: inout Set<String>
    ) throws {
        try validateProvenance(entry)
        guard ids.insert(entry.id).inserted else {
            throw ValidationError.duplicate("id \(entry.id)")
        }
        guard resources.insert(entry.resource).inserted else {
            throw ValidationError.duplicate("resource \(entry.resource)")
        }
        guard URL(fileURLWithPath: entry.resource).pathExtension.lowercased() == "cube",
              isSafeRelativePath(entry.resource) else {
            throw ValidationError.invalid("\(entry.id) must reference a safe relative .cube resource")
        }
        guard let url = resourceURL(for: entry, bundle: bundle) else {
            throw ValidationError.missingResource(entry.resource)
        }
        do {
            let lut = try CubeLUT(url: url, category: entry.category, source: .bundled, displayName: entry.name)
            guard lut.source == .bundled, lut.name == entry.name, lut.category == entry.category else {
                throw ValidationError.invalid("\(entry.id) metadata does not match the parsed LUT")
            }
        } catch {
            throw ValidationError.invalid("\(entry.id) is not a valid supported 3D LUT: \(error.localizedDescription)")
        }
    }

    private static func validateProvenance(_ entry: BundledLookManifest.Entry) throws {
        let fields: [(String, String)] = [
            ("id", entry.id), ("name", entry.name), ("category", entry.category),
            ("resource", entry.resource), ("sourceAuthor", entry.sourceAuthor),
            ("source", entry.source), ("license", entry.license),
            ("attribution", entry.attribution), ("redistribution", entry.redistribution),
            ("approval.recordID", entry.approval.recordID), ("approval.reviewer", entry.approval.reviewer),
            ("approval.approvedAt", entry.approval.approvedAt), ("approval.notes", entry.approval.notes),
        ]
        for (label, value) in fields where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingField("\(entry.id).\(label)")
        }
        guard entry.license == "MIT License (Lumo project license)" else {
            throw ValidationError.invalid("\(entry.id).license is not an approved redistributable license")
        }
        guard entry.approval.status == "approved" else {
            throw ValidationError.invalid("\(entry.id).approval.status must be approved")
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    enum ValidationError: LocalizedError, Sendable {
        case invalid(String)
        case missingField(String)
        case missingResource(String)
        case duplicate(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let message): return message
            case .missingField(let field): return "missing required field \(field)"
            case .missingResource(let resource): return "missing bundled resource \(resource)"
            case .duplicate(let value): return "duplicate manifest value: \(value)"
            }
        }
    }
}
