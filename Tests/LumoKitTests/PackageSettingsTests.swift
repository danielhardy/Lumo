import XCTest
@testable import LumoKit

/// Phase 2 Step 8's ship gate, and the only thing that can hold it.
///
/// Step 8 *is* the build setting. If `.swiftLanguageMode(.v6)` comes off a target, or the manifest
/// drops back to a 5.x tools version, the compiler quietly stops enforcing everything Steps 4–7
/// were built to satisfy — and every test still passes, because nothing observable changes. That is
/// the same shape as the second `CIContext` in `RenderStackTests`: an invariant with no runtime
/// trace, which is exactly the kind that needs looking at rather than asserting.
///
/// Read as source text on purpose. There is no API that reports "which language mode was this module
/// compiled in", and `#if swift(>=6)` reports the *compiler* version, not the language mode — it is
/// true today under a 5.9 manifest too, so it would pass against the very regression this guards.
final class PackageSettingsTests: XCTestCase {

    private static var manifest: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)   // Tests/LumoKitTests/PackageSettingsTests.swift
                .deletingLastPathComponent()            // Tests/LumoKitTests
                .deletingLastPathComponent()            // Tests
                .deletingLastPathComponent()            // package root
                .appendingPathComponent("Package.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testTheManifestDeclaresASwift6ToolsVersion() throws {
        let manifest = try Self.manifest
        let firstLine = try XCTUnwrap(manifest.split(separator: "\n").first)
        XCTAssertTrue(
            firstLine.hasPrefix("// swift-tools-version: 6"),
            """
            Step 8 raised the manifest to a Swift 6 tools version so `.swiftLanguageMode(.v6)` is \
            available. Found: \(firstLine)
            """
        )
    }

    /// Every target, not just the library. `LumoKit` was clean before this step; the executable and
    /// the test target were never checked at all, and the test target is where the one remaining
    /// diagnostic actually lived.
    func testEveryTargetIsInSwift6LanguageMode() throws {
        let manifest = try Self.manifest
        let declared = manifest.components(separatedBy: ".swiftLanguageMode(.v6)").count - 1
        XCTAssertEqual(
            declared, 3,
            """
            All three targets — LumoKit, Lumo, LumoKitTests — must declare Swift 6 language mode. \
            A 6.x tools version already defaults to it, so dropping these would not fail the build \
            today; it would only make the next tools-version change silently load-bearing. Found \
            \(declared) declaration(s).
            """
        )
        for target in ["LumoKit", "Lumo", "LumoKitTests"] {
            XCTAssertTrue(manifest.contains("name: \"\(target)\""), "\(target) is missing from the manifest")
        }
    }

    /// The module compiles with no concurrency escape hatches. Steps 4–7 promised zero, and the
    /// promise is what makes "Swift 6 mode is on" mean something — the mode is trivially satisfiable
    /// by opting out file by file.
    func testTheModuleUsesNoConcurrencyEscapeHatches() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))

        var offenders: [String] = []
        var scanned = 0
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Doc comments discuss these by name — only real code counts.
                guard !trimmed.hasPrefix("//") else { continue }
                for hatch in ["@unchecked Sendable", "nonisolated(unsafe)", "@preconcurrency"]
                where trimmed.contains(hatch) {
                    offenders.append("\(url.lastPathComponent): \(trimmed)")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 20, "expected to scan the whole module, saw \(scanned) files")
        XCTAssertEqual(offenders, [], "Swift 6 mode is only worth having without opt-outs")
    }
}
