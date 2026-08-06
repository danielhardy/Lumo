import XCTest
import CoreImage
@testable import LUTzyKit

/// Phase 2 Step 7's ship gate: **one `CIContext` in the render stack**.
///
/// The count to assert is 2, not 1, and the difference is the whole point. `RecipeExtractor` keeps
/// its own context by design (`docs/PHASE2_SPEC.md` §3): it sits outside the stack, never imports
/// `EditDocument`, never calls `RenderEngine`, and samples in a space pinned to sRGB regardless of
/// `WorkingSpace.current` — because a derived cube has to be *fit* in the space it will later be
/// *applied* in (§4.4). Folding it into the engine would quietly couple those two spaces together.
///
/// So the invariant is not "one context in the module". It is "one context in the render path, and
/// exactly one other, and we can name it".
///
/// **This reads source text, and that is deliberate.** A `CIContext` leaves no observable trace —
/// two of them render identically, cost twice the memory, and no runtime assertion can tell them
/// apart. `ImageProcessor` held the second one for five migration steps without a single test
/// noticing. The only way to keep it from coming back is to look.
final class RenderStackTests: XCTestCase {

    /// The module's source directory, found relative to this file rather than to the working
    /// directory — `swift test` and Xcode disagree about the latter.
    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)          // Tests/LUTzyKitTests/RenderStackTests.swift
            .deletingLastPathComponent()          // Tests/LUTzyKitTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // package root
            .appendingPathComponent("Sources/LUTzyKit")
    }

    private func swiftFiles() throws -> [URL] {
        let root = Self.sourcesDirectory
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
            "could not enumerate \(root.path)"
        )
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }

    /// Every file that constructs a `CIContext`, by name.
    private func filesConstructingAContext() throws -> Set<String> {
        var found: Set<String> = []
        for url in try swiftFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            // Skip the doc comments that *mention* `CIContext(` — only real constructions count.
            let constructs = text.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { return false }
                return trimmed.contains("CIContext(")
            }
            if constructs { found.insert(url.lastPathComponent) }
        }
        return found
    }

    func testOnlyTwoTypesInTheModuleOwnACIContext() throws {
        let files = try swiftFiles()
        XCTAssertGreaterThan(files.count, 20,
                             "expected to scan the whole module; found \(files.count) files under \(Self.sourcesDirectory.path)")

        let owners = try filesConstructingAContext()
        XCTAssertEqual(
            owners,
            ["RenderEngine.swift", "RecipeExtractor.swift"],
            """
            The render stack owns exactly one CIContext (RenderEngine), and RecipeExtractor keeps a \
            second by design — see PHASE2_SPEC §3 and §4.4. A third is a regression: it means some \
            code path is rendering outside the actor that owns the pipeline. If a new context is \
            genuinely warranted, say why here and update this list deliberately.
            """
        )
    }

    /// Thumbnails were the other half of Step 7, and they deliberately did **not** move onto the
    /// engine: `CGImageSource` reads a file's embedded preview, so a 30 MB DNG thumbnails in
    /// milliseconds without being demosaiced. Routing them through the actor would queue every
    /// filmstrip tile behind the preview render for no gain.
    ///
    /// Pinned as source text for the same reason as above — a `CIImage` creeping in here would
    /// change the cost profile and nothing else.
    func testThumbnailsStayOutOfCoreImage() throws {
        let url = Self.sourcesDirectory.appendingPathComponent("Models/Thumbnails.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let code = text.split(separator: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///")
        }.joined(separator: "\n")

        for symbol in ["CIContext", "CIImage", "CIFilter", "RenderEngine"] {
            XCTAssertFalse(code.contains(symbol),
                           "\(symbol) in Thumbnails would put the filmstrip on the render path")
        }
        XCTAssertTrue(code.contains("CGImageSource"), "thumbnails should still read embedded previews")
    }
}
