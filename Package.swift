// swift-tools-version: 6.0
import PackageDescription
import Foundation

private enum StarterLookPackageValidationError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let message): return message
        }
    }
}

/// Keep the package fail-closed even when a developer runs only `swift build` and not the test
/// suite. The runtime loader performs the same checks with the real CubeLUT parser; this manifest
/// check is intentionally Foundation-only because Package.swift cannot import the target.
private func validateStarterLookPackage() throws {
    let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let resourceDirectory = packageDirectory
        .appendingPathComponent("Sources/LumoKit/Resources/StarterLooks", isDirectory: true)
    let manifestURL = resourceDirectory.appendingPathComponent("manifest.json")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
    guard let manifest = object as? [String: Any],
          let schemaVersion = manifest["schemaVersion"] as? Int,
          schemaVersion == 1,
          let acknowledgement = manifest["acknowledgement"] as? String,
          !acknowledgement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let entries = manifest["looks"] as? [[String: Any]],
          !entries.isEmpty else {
        throw StarterLookPackageValidationError.invalid("Starter Look manifest is incomplete")
    }

    var ids = Set<String>()
    var resources = Set<String>()
    for entry in entries {
        func requiredString(_ key: String) throws -> String {
            guard let value = entry[key] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StarterLookPackageValidationError.invalid("Starter Look entry is missing \(key)")
            }
            return value
        }

        let id = try requiredString("id")
        let resource = try requiredString("resource")
        _ = try requiredString("name")
        _ = try requiredString("category")
        _ = try requiredString("sourceAuthor")
        _ = try requiredString("source")
        let license = try requiredString("license")
        guard license == "MIT License (Lumo project license)" else {
            throw StarterLookPackageValidationError.invalid("Starter Look \(id) has no approved redistributable license")
        }
        _ = try requiredString("attribution")
        _ = try requiredString("redistribution")
        guard let approval = entry["approval"] as? [String: Any],
              approval["status"] as? String == "approved" else {
            throw StarterLookPackageValidationError.invalid("Starter Look \(id) is not approved")
        }
        for key in ["recordID", "reviewer", "approvedAt", "notes"] {
            guard let value = approval[key] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StarterLookPackageValidationError.invalid("Starter Look \(id) is missing approval.\(key)")
            }
        }
        guard ids.insert(id).inserted, resources.insert(resource).inserted else {
            throw StarterLookPackageValidationError.invalid("Starter Look manifest contains a duplicate id or resource")
        }
        guard resource.lowercased().hasSuffix(".cube"),
              !resource.hasPrefix("/"),
              !resource.split(separator: "/").contains("..") else {
            throw StarterLookPackageValidationError.invalid("Starter Look \(id) has an unsafe resource path")
        }

        let url = resourceDirectory.appendingPathComponent(resource)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StarterLookPackageValidationError.invalid("Starter Look \(id) is missing \(resource)")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        var size: Int?
        var rows = 0
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "#", maxSplits: 1)[0]
                .trimmingCharacters(in: .whitespaces)
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard !parts.isEmpty else { continue }
            if parts[0] == "LUT_3D_SIZE" {
                guard parts.count == 2, let parsed = Int(parts[1]), (2...65).contains(parsed), size == nil else {
                    throw StarterLookPackageValidationError.invalid("Starter Look \(id) has an invalid LUT_3D_SIZE")
                }
                size = parsed
            } else if parts.count == 3, parts.allSatisfy({ Float($0) != nil && Float($0)!.isFinite }) {
                rows += 1
            } else if parts.allSatisfy({ Float($0) != nil }) {
                throw StarterLookPackageValidationError.invalid("Starter Look \(id) has a malformed numeric row")
            }
        }
        guard let size, rows == size * size * size else {
            throw StarterLookPackageValidationError.invalid("Starter Look \(id) does not contain exactly size³ rows")
        }
    }
}

do {
    try validateStarterLookPackage()
} catch {
    fatalError("Starter Look package validation failed: \(error)")
}

// Lumo is split into a library plus a thin `@main` executable so the app's own
// code can be unit-tested: `@testable` cannot import an executable target.
// Everything of substance lives in LumoKit; the Lumo target is just the entry
// point, the app delegate, and the asset catalog.
let package = Package(
    name: "Lumo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lumo", targets: ["Lumo"]),
        .library(name: "LumoKit", targets: ["LumoKit"]),
    ],
    targets: [
        .target(
            name: "LumoKit",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("Photos"),
                .linkedFramework("PhotosUI"),
            ]
        ),
        .executableTarget(
            name: "Lumo",
            dependencies: ["LumoKit"],
            exclude: ["Assets.xcassets", "Lumo.entitlements"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LumoKitTests",
            dependencies: ["LumoKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
