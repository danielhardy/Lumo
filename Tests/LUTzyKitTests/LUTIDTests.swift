import XCTest
@testable import LUTzyKit

/// `LUTID` is the one Step 2 type that can be wrong in a way nothing catches until a user loses work.
///
/// A document stores a LUT by ID and resolves it against the library. If that ID were minted per
/// scan — a `UUID`, say — every saved and every undo document would silently stop resolving the next
/// time the library was rescanned, and `saveDerivedLUT` triggers a rescan. The failure is quiet: the
/// document is intact, the LUT is on disk, the lookup just misses. So the ID's determinism across a
/// rescan is tested directly. See `docs/PHASE2_SPEC.md` §4.3 and §7.
@MainActor
final class LUTIDTests: TempDirectoryTestCase {

    private func waitForScan(_ library: LUTLibrary, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while library.isScanning {
            if Date() > deadline { XCTFail("scan did not finish within \(timeout)s"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Determinism

    func testIDIsTheFilePathAndIsStableAcrossReparsing() throws {
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 4), named: "Look.cube", in: tempDirectory
        )

        let first = try CubeLUT(url: url)
        let second = try CubeLUT(url: url)

        XCTAssertEqual(first.lutID, second.lutID, "the same file must always yield the same ID")
        XCTAssertEqual(first.lutID.raw, url.path)
        XCTAssertFalse(first.lutID.isDerived)
    }

    /// The one case where an ID legitimately is not reproducible: a LUT that exists only in memory,
    /// before the user saves it. `isDerived` is how a persistence layer can tell.
    func testInMemoryDerivedLUTsGetASyntheticID() {
        let cube = [SIMD3<Float>](repeating: .zero, count: 8)
        let a = CubeLUT(cube: cube, size: 2, name: "Derived Look")
        let b = CubeLUT(cube: cube, size: 2, name: "Derived Look")

        XCTAssertTrue(a.lutID.isDerived)
        XCTAssertNotEqual(a.lutID, b.lutID, "two in-memory derivations are two different LUTs")

        // A file-backed LUT is never mistaken for one.
        let saved = CubeLUT(cube: cube, size: 2, name: "Saved",
                            sourceURL: tempDirectory.appendingPathComponent("Saved.cube"))
        XCTAssertFalse(saved.lutID.isDerived)
        XCTAssertEqual(saved.lutID.raw, tempDirectory.appendingPathComponent("Saved.cube").path)
    }

    // MARK: - Resolution across a rescan

    /// The regression that matters: hold an ID, rescan the library the way `saveDerivedLUT` does,
    /// and the ID must still resolve to the same LUT.
    func testResolutionSurvivesARescan() async throws {
        let library = LUTLibrary()
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 4), named: "Keeper.cube", in: tempDirectory)

        library.scan(tempDirectory)
        try await waitForScan(library)
        let stored = try XCTUnwrap(library.allLUTs.first).lutID

        // What saving a derived LUT does: a new .cube lands in the folder and the library rescans.
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 4), named: "Derived-01.cube", in: tempDirectory)
        library.scan(tempDirectory)
        try await waitForScan(library)
        XCTAssertEqual(library.allLUTs.count, 2, "the rescan should have picked up the new file")

        let resolved = try XCTUnwrap(
            library.allLUTs.first(matching: stored),
            "the stored ID no longer resolves after a rescan — a document holding it has lost its LUT"
        )
        XCTAssertEqual(resolved.name, "Keeper")
        XCTAssertEqual(resolved.lutID, stored)
    }

    /// Resolution has to be exact: a stale ID must miss rather than match a neighbour, or a rescan
    /// would quietly swap one look for another.
    func testResolutionMissesForALUTThatIsGone() async throws {
        let library = LUTLibrary()
        let doomed = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 4), named: "Doomed.cube", in: tempDirectory
        )
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 4), named: "Survivor.cube", in: tempDirectory)

        library.scan(tempDirectory)
        try await waitForScan(library)
        let stored = try XCTUnwrap(library.allLUTs.first(where: { $0.name == "Doomed" })).lutID

        try FileManager.default.removeItem(at: doomed)
        library.scan(tempDirectory)
        try await waitForScan(library)

        XCTAssertEqual(library.allLUTs.count, 1)
        XCTAssertNil(library.allLUTs.first(matching: stored),
                     "a deleted LUT must not resolve to whatever else is in the folder")
    }
}
