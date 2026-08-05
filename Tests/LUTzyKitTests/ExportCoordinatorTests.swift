import XCTest
import CoreImage
@testable import LUTzyKit

/// Export used to be untestable: the work was welded to `NSSavePanel` inside
/// `AppViewModel`, so there was no way to run it headless. Splitting each
/// operation into a `perform…` core plus a panel wrapper is what these tests
/// are standing on.
@MainActor
final class ExportCoordinatorTests: TempDirectoryTestCase {

    private func makeSources(_ names: [String]) throws -> [ExportCoordinator.BatchItem] {
        try names.map { name in
            let url = try Fixtures.writeJPEG(
                width: 32, height: 24, orientation: 1, named: "\(name).jpg", in: tempDirectory
            )
            return ExportCoordinator.BatchItem(url: url, data: nil, name: name)
        }
    }

    private func destinationFolder() throws -> URL {
        let folder = tempDirectory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Naming

    func testExportBaseNameAppendsLUTWithUnderscores() throws {
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "LEICA BW NAT.cube", in: tempDirectory
        )
        let lut = try CubeLUT(url: url)

        XCTAssertEqual(
            ExportCoordinator.exportBaseName(source: "R0010966", lut: lut),
            "R0010966_LEICA_BW_NAT",
            "spaces in a LUT name should become underscores"
        )
        XCTAssertEqual(
            ExportCoordinator.exportBaseName(source: "R0010966", lut: nil),
            "R0010966",
            "no LUT means no suffix"
        )
    }

    func testDefaultFileNameUsesTheFormatExtension() {
        XCTAssertEqual(
            ExportCoordinator.defaultFileName(source: "photo", lut: nil, format: .jpeg),
            "photo.jpg"
        )
        XCTAssertEqual(
            ExportCoordinator.defaultFileName(source: "photo", lut: nil, format: .tiff),
            "photo.tif"
        )
    }

    // MARK: - Single export

    func testPerformExportWritesTheFile() async throws {
        let coordinator = ExportCoordinator()
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }
        coordinator.onError = { XCTFail("unexpected error: \($0)") }

        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let destination = tempDirectory.appendingPathComponent("out.jpg")
        coordinator.performExport(image, to: destination)

        try await waitUntil { !coordinator.isExporting }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(Fixtures.storedSize(of: destination), CGSize(width: 16, height: 16))
        XCTAssertEqual(statuses.last, "Exported: out.jpg")
    }

    func testPerformExportReportsFailureThroughOnError() async throws {
        let coordinator = ExportCoordinator()
        var errors: [String] = []
        coordinator.onError = { errors.append($0) }

        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        // A directory that doesn't exist — the encode succeeds, the write fails.
        let destination = tempDirectory
            .appendingPathComponent("no-such-folder")
            .appendingPathComponent("out.jpg")
        coordinator.performExport(image, to: destination)

        try await waitUntil { !coordinator.isExporting }
        XCTAssertEqual(errors.count, 1, "a failed write must surface, not vanish")
        XCTAssertTrue(errors[0].hasPrefix("Export failed:"), errors[0])
    }

    // MARK: - Batch export

    func testBatchExportWritesEveryImage() async throws {
        let coordinator = ExportCoordinator()
        coordinator.format = .png
        coordinator.onError = { XCTFail("unexpected error: \($0)") }

        let items = try makeSources(["a", "b", "c"])
        let folder = try destinationFolder()

        let outcome = await coordinator.performBatchExport(items, lut: nil, intensity: 1, to: folder)

        XCTAssertEqual(outcome, .init(exported: 3, failed: 0, total: 3))
        for name in ["a", "b", "c"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(name).png").path),
                "\(name).png should have been written"
            )
        }
        XCTAssertFalse(coordinator.isExporting, "the run should clear its own busy flag")
        XCTAssertEqual(coordinator.batchProgress, 0, "progress should reset when the run ends")
    }

    func testBatchExportAppliesTheLUTToTheFilenames() async throws {
        let coordinator = ExportCoordinator()
        coordinator.format = .jpeg
        let lutURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "My Look.cube", in: tempDirectory
        )
        let lut = try CubeLUT(url: lutURL)

        let items = try makeSources(["shot"])
        let folder = try destinationFolder()
        _ = await coordinator.performBatchExport(items, lut: lut, intensity: 1, to: folder)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("shot_My_Look.jpg").path),
            "the LUT name should be in the exported filename"
        )
    }

    /// A failure partway through must not abort the run — the user should get
    /// every image that could be exported, and a count of the ones that couldn't.
    func testBatchExportSkipsAndCountsFailuresWithoutAborting() async throws {
        let coordinator = ExportCoordinator()
        coordinator.onError = { XCTFail("a per-item failure should not raise: \($0)") }

        var items = try makeSources(["good1", "good2"])
        // A source that cannot be decoded, sandwiched between two good ones.
        let broken = tempDirectory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: broken)
        items.insert(ExportCoordinator.BatchItem(url: broken, data: nil, name: "broken"), at: 1)

        let folder = try destinationFolder()
        let outcome = await coordinator.performBatchExport(items, lut: nil, intensity: 1, to: folder)

        XCTAssertEqual(outcome, .init(exported: 2, failed: 1, total: 3))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("good1.jpg").path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("good2.jpg").path),
            "the item after the failure must still be exported"
        )
    }

    func testBatchExportDoesNotOverwriteSameNamedSources() async throws {
        let coordinator = ExportCoordinator()

        // Two files with the same basename in different subfolders — exactly
        // what a recursive source-folder scan produces.
        let subA = tempDirectory.appendingPathComponent("a")
        let subB = tempDirectory.appendingPathComponent("b")
        for sub in [subA, subB] {
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try Fixtures.writeJPEG(width: 16, height: 16, orientation: 1, named: "DSC001.jpg", in: sub)
        }
        let items = [
            ExportCoordinator.BatchItem(url: subA.appendingPathComponent("DSC001.jpg"), data: nil, name: "DSC001"),
            ExportCoordinator.BatchItem(url: subB.appendingPathComponent("DSC001.jpg"), data: nil, name: "DSC001"),
        ]

        let folder = try destinationFolder()
        let outcome = await coordinator.performBatchExport(items, lut: nil, intensity: 1, to: folder)

        XCTAssertEqual(outcome.exported, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("DSC001.jpg").path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("DSC001 2.jpg").path),
            "the second file must not overwrite the first"
        )
    }

    func testBatchExportReportsProgressAsItGoes() async throws {
        let coordinator = ExportCoordinator()
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }

        let items = try makeSources(["a", "b"])
        let folder = try destinationFolder()
        _ = await coordinator.performBatchExport(items, lut: nil, intensity: 1, to: folder)

        XCTAssertTrue(statuses.contains("Exporting 0 of 2…"), "\(statuses)")
        XCTAssertTrue(statuses.contains("Exporting 2 of 2…"), "\(statuses)")
        XCTAssertEqual(statuses.last, "Exported 2 images to out")
    }

    func testBatchExportHonorsIntensity() async throws {
        // A cube that maps everything to black, applied at 0, must leave the
        // exported pixels alone — this is what keeps Export All matching the
        // preview when the slider isn't at 100%.
        let coordinator = ExportCoordinator()
        coordinator.format = .png
        let lut = CubeLUT(cube: [SIMD3<Float>](repeating: .zero, count: 8), size: 2, name: "toBlack")

        let items = try makeSources(["subject"])
        let folder = try destinationFolder()
        _ = await coordinator.performBatchExport(items, lut: lut, intensity: 0, to: folder)

        let exported = folder.appendingPathComponent("subject_toBlack.png")
        let image = try XCTUnwrap(CIImage(contentsOf: exported))
        let pixel = try XCTUnwrap(firstPixel(of: image))
        XCTAssertGreaterThan(pixel.0 + pixel.1 + pixel.2, 30,
                             "intensity 0 should not have blacked the image out")
    }

    // MARK: - Summary text

    func testSummaryWordingCoversSingularPluralAndFailures() {
        let folder = URL(fileURLWithPath: "/tmp/Exports")
        XCTAssertEqual(
            ExportCoordinator.summary(for: .init(exported: 1, failed: 0, total: 1), folder: folder),
            "Exported 1 image to Exports"
        )
        XCTAssertEqual(
            ExportCoordinator.summary(for: .init(exported: 3, failed: 0, total: 3), folder: folder),
            "Exported 3 images to Exports"
        )
        XCTAssertEqual(
            ExportCoordinator.summary(for: .init(exported: 2, failed: 1, total: 3), folder: folder),
            "Exported 2 of 3 (1 failed) to Exports"
        )
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("condition not met within \(timeout)s") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func firstPixel(of image: CIImage) -> (CGFloat, CGFloat, CGFloat)? {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { ptr in
            context.render(
                image, toBitmap: ptr.baseAddress!, rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            )
        }
        return (CGFloat(bytes[0]), CGFloat(bytes[1]), CGFloat(bytes[2]))
    }
}
