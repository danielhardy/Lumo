import XCTest
@testable import LumoKit

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

    func testFileIDUsesTheCanonicalPath() throws {
        let folder = tempDirectory.appendingPathComponent("Looks")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Canonical.cube", in: folder
        )
        let alternate = folder.appendingPathComponent(".").appendingPathComponent("Canonical.cube")

        XCTAssertEqual(try CubeLUT(url: url).lutID, try CubeLUT(url: alternate).lutID)
    }

    /// A LUT that exists only in memory gets a `derived://` ID, and that ID follows its **contents**.
    ///
    /// **Step 9 reversed this property, deliberately.** It used to be a `UUID`, so constructing the
    /// same cube twice produced two identities. `docs/PHASE2_SPEC.md` §4.3's objection to a `UUID` is
    /// that it mints fresh identity on construction, which is exactly what that did — one level down
    /// from the rescan case the section is written about. Identity now follows the table, so the same
    /// cube is the same LUT: they render identically and are interchangeable in `LUTFilterCache`.
    ///
    /// What this does **not** buy, and must not be read as buying: re-deriving from the same (RAW,
    /// JPG) pair does not reproduce the ID. `RecipeExtractor` samples with
    /// `SystemRandomNumberGenerator`, so a second derive fits a different cube.
    func testAnInMemoryDerivedLUTGetsAContentDerivedID() {
        let cube = [SIMD3<Float>](repeating: .zero, count: 8)
        let a = CubeLUT(cube: cube, size: 2, name: "Derived Look")
        let b = CubeLUT(cube: cube, size: 2, name: "Derived Look")

        XCTAssertTrue(a.lutID.isDerived)
        XCTAssertEqual(a.lutID, b.lutID, "identity follows the cube table, so the same table is one LUT")

        // A different table is a different LUT, or the ID would be telling us nothing.
        var otherCube = cube
        otherCube[3] = SIMD3(0.5, 0.5, 0.5)
        let other = CubeLUT(cube: otherCube, size: 2, name: "Derived Look")
        XCTAssertNotEqual(a.lutID, other.lutID, "a different cube must not collide with this one")

        // ...and so is the same table under a different name, which is what keeps two derives from
        // different source pairs distinct in the registry.
        let renamed = CubeLUT(cube: cube, size: 2, name: "Other Look")
        XCTAssertNotEqual(a.lutID, renamed.lutID)

        // A file-backed LUT is never mistaken for one.
        let saved = CubeLUT(cube: cube, size: 2, name: "Saved",
                            sourceURL: tempDirectory.appendingPathComponent("Saved.cube"))
        XCTAssertFalse(saved.lutID.isDerived)
        XCTAssertEqual(saved.lutID.raw, tempDirectory.appendingPathComponent("Saved.cube").path)
    }

    /// The hash has to come from the cube, not from `Hasher`.
    ///
    /// Swift's `Hasher` is seeded per process, so an ID built from it would be stable within a launch
    /// and silently different across launches — the same class of failure §4.3 warns about, wearing a
    /// different hat, and invisible to every single-process test. Pinning one known table against its
    /// literal ID is the only way to catch it from inside the suite.
    ///
    /// The literal is a value **recorded from the implementation**, not derived independently — a
    /// golden constant. That is the whole point: what it proves is not that the digest is *correct*
    /// but that it is *the same one tomorrow*, which no assertion computed at runtime can establish.
    /// Its stability was confirmed across separate `swift test` processes before it was written down.
    func testTheDerivedIDIsStableAcrossProcesses() {
        let cube = [SIMD3<Float>](repeating: .zero, count: 8)
        let lut = CubeLUT(cube: cube, size: 2, name: "Pinned")
        XCTAssertEqual(
            lut.id, "derived://Pinned/df2a1e35e368561a",
            """
            The derived ID changed. If that was deliberate — a different hash, a different layout — \
            update this literal. If it was not, the likely cause is a per-process seed (Swift's \
            Hasher), which would make every persisted document stop resolving after a relaunch.
            """
        )
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

    /// A folder scan can never produce a `derived://` ID.
    ///
    /// This is what makes registry-and-library resolution order unobservable, which in turn is why a
    /// mutation swapping that order is *equivalent* rather than a coverage gap — see the note in
    /// `scripts/mutate-step9.sh`. The reasoning is that `LUTLibrary.scanSync` only ever builds
    /// `CubeLUT(url:)`, whose ID is a filesystem path and so begins with `/`. That is airtight today
    /// and load-bearing for an argument recorded in the migration notes, so it is worth a test rather
    /// than a paragraph: if the library ever starts minting synthetic IDs, the equivalence quietly
    /// stops holding and a derived LUT could resolve to a file.
    func testAScannedLibraryNeverProducesADerivedID() async throws {
        let library = LUTLibrary()
        let nested = tempDirectory.appendingPathComponent("Looks")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "Flat.cube", in: tempDirectory)
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 2), named: "Nested.cube", in: nested)

        library.scan(tempDirectory)
        try await waitForScan(library)

        XCTAssertEqual(library.allLUTs.count, 2)
        for lut in library.allLUTs {
            XCTAssertFalse(lut.lutID.isDerived, "\(lut.name) came out of a scan with a derived:// ID")
            XCTAssertTrue(lut.id.hasPrefix("/"), "a scanned LUT's ID is a path")
        }
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
