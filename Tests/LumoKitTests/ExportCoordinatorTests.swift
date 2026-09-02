import XCTest
import CoreImage
@testable import LumoKit

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

    func testLastUsedFormatPersistsAcrossSingleAndBatchExports() async throws {
        let coordinator = ExportCoordinator()
        XCTAssertEqual(coordinator.lastUsedFormat, .jpeg)

        coordinator.performExport(
            source: try makeSource(), document: EditDocument(), lut: nil,
            format: .tiff, to: tempDirectory.appendingPathComponent("first.tif")
        )
        try await waitUntil { !coordinator.isExporting }
        XCTAssertEqual(coordinator.lastUsedFormat, .tiff)

        let batchItem = try XCTUnwrap(makeSources(["batch"]).first)
        _ = await coordinator.performBatchExport(
            [batchItem], document: EditDocument(), lut: nil,
            format: .png, to: try destinationFolder()
        )
        XCTAssertEqual(coordinator.lastUsedFormat, .png)
        XCTAssertEqual(ExportCoordinator().lastUsedFormat, .jpeg,
                       "the remembered format belongs to one coordinator session")
    }

    /// An `ImageSource` for a real file on disk, so the engine has something to decode.
    private func makeSource(width: Int = 16, height: Int = 16, named name: String = "src.png") throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(width: width, height: height, named: name, in: tempDirectory)
        return ImageSource(url: url, nativeExtent: CGSize(width: width, height: height))
    }

    func testPerformExportWritesTheFile() async throws {
        let coordinator = ExportCoordinator()
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }
        coordinator.onError = { XCTFail("unexpected error: \($0)") }

        let destination = tempDirectory.appendingPathComponent("out.jpg")
        coordinator.performExport(
            source: try makeSource(), document: EditDocument(), lut: nil, format: .jpeg, to: destination
        )

        try await waitUntil { !coordinator.isExporting }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(Fixtures.storedSize(of: destination), CGSize(width: 16, height: 16))
        XCTAssertEqual(statuses.last, "Exported: out.jpg")
    }

    func testPerformExportReportsAFailedWriteThroughOnError() async throws {
        let coordinator = ExportCoordinator()
        var errors: [String] = []
        coordinator.onError = { errors.append($0) }

        // A directory that doesn't exist — the encode succeeds, the write fails.
        let destination = tempDirectory
            .appendingPathComponent("no-such-folder")
            .appendingPathComponent("out.jpg")
        coordinator.performExport(
            source: try makeSource(), document: EditDocument(), lut: nil, format: .jpeg, to: destination
        )

        try await waitUntil { !coordinator.isExporting }
        XCTAssertEqual(errors.count, 1, "a failed write must surface, not vanish")
        XCTAssertTrue(errors[0].hasPrefix("Export failed:"), errors[0])
        // Not merely "an error appeared": a *write* failure has to be distinguishable from the
        // encode failure below, or one message would satisfy both tests.
        XCTAssertNotEqual(errors[0], "Export failed: Export failed",
                          "this path should report the filesystem's error, not the encoder's")
    }

    /// The other half of the failure surface: the *encode* fails rather than the write. A bare
    /// "some error appeared" assertion would be satisfied by either, and by neither reaching the
    /// user — this pins that an engine failure gets reported too, and that the busy flag clears.
    func testPerformExportReportsAFailedEncodeThroughOnError() async throws {
        let fake = FakeRenderEngine()
        await fake.setShouldFailEncode(true)
        let coordinator = ExportCoordinator(engine: fake)
        var errors: [String] = []
        coordinator.onError = { errors.append($0) }
        coordinator.onStatus = { _ in }

        let destination = tempDirectory.appendingPathComponent("out.jpg")
        coordinator.performExport(
            source: try makeSource(), document: EditDocument(), lut: nil, format: .jpeg, to: destination
        )

        try await waitUntil { !coordinator.isExporting }
        XCTAssertEqual(errors, ["Export failed: Export failed"],
                       "a failed encode must surface with the engine's own error")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path),
                       "a failed encode must not leave a file behind")
    }

    // MARK: - Batch export

    func testBatchExportWritesEveryImage() async throws {
        let coordinator = ExportCoordinator()
        coordinator.onError = { XCTFail("unexpected error: \($0)") }

        let items = try makeSources(["a", "b", "c"])
        let folder = try destinationFolder()

        let outcome = await coordinator.performBatchExport(
            items, document: EditDocument(), lut: nil, format: .png, to: folder
        )

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
        let lutURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "My Look.cube", in: tempDirectory
        )
        let lut = try CubeLUT(url: lutURL)

        let items = try makeSources(["shot"])
        let folder = try destinationFolder()
        _ = await coordinator.performBatchExport(
            items, document: EditDocument(), lut: lut, format: .jpeg, to: folder
        )

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
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }

        var items = try makeSources(["good1", "good2"])
        // A source that cannot be decoded, sandwiched between two good ones.
        let broken = tempDirectory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: broken)
        items.insert(ExportCoordinator.BatchItem(url: broken, data: nil, name: "broken"), at: 1)

        let folder = try destinationFolder()
        let outcome = await coordinator.performBatchExport(
            items, document: EditDocument(), lut: nil, format: .jpeg, to: folder
        )

        XCTAssertEqual(outcome, .init(exported: 2, failed: 1, total: 3))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("good1.jpg").path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("good2.jpg").path),
            "the item after the failure must still be exported"
        )
        XCTAssertTrue(
            statuses.contains { $0.hasPrefix("Skipped broken:") },
            "the failed source should be reported while the batch continues"
        )
    }

    /// HEIF depends on the host's Image I/O/HEVC encoder. A failure from that optional encoder is
    /// still an ordinary per-item batch failure: no destination is committed and later items run.
    func testBatchHEIFEncoderFailureIsIsolatedToTheItem() async throws {
        let fake = FakeRenderEngine()
        await fake.setShouldFailEncode(true)
        let coordinator = ExportCoordinator(engine: fake)
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }

        let folder = try destinationFolder()
        let outcome = await coordinator.performBatchExport(
            try makeSources(["first", "second"]),
            document: EditDocument(),
            lut: nil,
            format: .heif,
            to: folder
        )

        XCTAssertEqual(outcome, .init(exported: 0, failed: 2, total: 2))
        XCTAssertTrue(statuses.contains { $0.hasPrefix("Skipped first:") })
        XCTAssertTrue(statuses.contains { $0.hasPrefix("Skipped second:") })
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .contains { $0.hasSuffix(".heic") || $0.hasSuffix(".partial") },
            "an unavailable HEIF encoder must not leave a partial or committed output"
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
        let outcome = await coordinator.performBatchExport(
            items, document: EditDocument(), lut: nil, format: .jpeg, to: folder
        )

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
        _ = await coordinator.performBatchExport(
            items, document: EditDocument(), lut: nil, format: .jpeg, to: folder
        )

        XCTAssertTrue(statuses.contains("Exporting 0 of 2…"), "\(statuses)")
        XCTAssertTrue(statuses.contains("Exporting 2 of 2…"), "\(statuses)")
        XCTAssertTrue(statuses.contains("Exporting 0 of 2… a"), "current item missing: \(statuses)")
        XCTAssertTrue(statuses.contains("Exporting 1 of 2… b"), "current item missing: \(statuses)")
        XCTAssertEqual(statuses.last, "Exported 2 images to out")
    }

    func testBatchExportCanBeCancelledBetweenItemsAndKeepsCompletedFiles() async throws {
        let fake = FakeRenderEngine()
        await fake.gateEncodeAfterFirst()
        let coordinator = ExportCoordinator(engine: fake)
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }

        let items = try makeSources(["first", "second", "third"])
        let folder = try destinationFolder()
        let task = Task {
            await coordinator.performBatchExport(
                items, document: EditDocument(), lut: nil, format: .png, to: folder
            )
        }

        try await waitUntil { coordinator.batchCurrentItem == "second" }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("first.png").path
        ))
        coordinator.cancelBatchExport()
        await fake.releaseEncode()

        let outcome = await task.value
        XCTAssertEqual(outcome, .init(exported: 1, failed: 0, total: 3, cancelled: true))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("first.png").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("second.png").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("third.png").path
        ))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .contains { $0.hasSuffix(".partial") },
            "cancellation must remove incomplete temporary outputs"
        )
        XCTAssertTrue(statuses.contains { $0.hasPrefix("Export cancelled after 1 of 3") })
    }

    func testBatchExportKeepsFullResolutionWorkBoundedToOneItem() async throws {
        let fake = FakeRenderEngine()
        let coordinator = ExportCoordinator(engine: fake)
        let folder = try destinationFolder()
        _ = await coordinator.performBatchExport(
            try makeSources(["a", "b", "c", "d"]),
            document: EditDocument(), lut: nil, format: .png, to: folder
        )

        let maxConcurrentEncodes = await fake.maxConcurrentEncodes
        XCTAssertEqual(maxConcurrentEncodes, 1)
    }

    /// A cube that maps everything to black, so both ends of the slider are unmistakable in the
    /// written file: at full strength the export must be black, at zero it must not. Asserting only
    /// the zero end would pass against a batch that ignored the LUT entirely.
    func testBatchExportHonorsTheDocumentsIntensity() async throws {
        let lut = CubeLUT(cube: [SIMD3<Float>](repeating: .zero, count: 8), size: 2, name: "toBlack")
        let folder = try destinationFolder()

        func exportSum(intensity: Double, named name: String) async throws -> CGFloat {
            let coordinator = ExportCoordinator()
            let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: intensity))
            _ = await coordinator.performBatchExport(
                try makeSources([name]), document: document, lut: lut, format: .png, to: folder
            )
            let exported = folder.appendingPathComponent("\(name)_toBlack.png")
            let image = try XCTUnwrap(CIImage(contentsOf: exported))
            let pixel = try XCTUnwrap(firstPixel(of: image))
            return pixel.0 + pixel.1 + pixel.2
        }

        let atZero = try await exportSum(intensity: 0, named: "slider-off")
        let atFull = try await exportSum(intensity: 1, named: "slider-on")

        XCTAssertGreaterThan(atZero, 30, "intensity 0 should not have blacked the image out")
        XCTAssertLessThan(atFull, 6, "intensity 1 of a to-black cube should have blacked it out")
    }

    func testBatchExportUsesEachAssetsPersistedDocument() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let urls = try ["first", "second"].map {
            try Fixtures.writeGradientPNG(width: 48, height: 32, named: "\($0).png", in: sourceFolder)
        }
        let store = EditDocumentStore(fileURL: tempDirectory.appendingPathComponent("edits.json"))
        let firstDocument = EditDocument(adjustments: [.exposure(ev: 0.25)])
        let secondDocument = EditDocument(adjustments: [.vibrance(amount: 0.75)])
        for (url, document) in zip(urls, [firstDocument, secondDocument]) {
            try await store.save(
                document,
                for: EditSourceReference(assetID: .file(url), url: url)
            )
        }

        let fake = FakeRenderEngine()
        let coordinator = ExportCoordinator(engine: fake, editStore: store)
        let items = urls.map {
            ExportCoordinator.BatchItem(url: $0, data: nil, name: $0.deletingPathExtension().lastPathComponent)
        }
        let outcome = await coordinator.performBatchExport(
            items, document: EditDocument(), lut: nil, format: .png, to: try destinationFolder()
        )

        XCTAssertEqual(outcome, .init(exported: 2, failed: 0, total: 2))
        let requests = await fake.encodeRequests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.contains { $0.source?.backing == .url(urls[0]) && $0.document == firstDocument })
        XCTAssertTrue(requests.contains { $0.source?.backing == .url(urls[1]) && $0.document == secondDocument })
        XCTAssertTrue(requests.allSatisfy { $0.scale == .full }, "batch export must never use a preview scale")
    }

    func testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals() async throws {
        let libraryFolder = tempDirectory.appendingPathComponent("selected-library")
        try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        let urls = try ["one", "two", "three"].map {
            try Fixtures.writeGradientPNG(width: 40, height: 24, named: "\($0).png", in: libraryFolder)
        }
        let store = EditDocumentStore(fileURL: tempDirectory.appendingPathComponent("selected-edits.json"))
        let documents = [
            EditDocument(adjustments: [.exposure(ev: 0.1)]),
            EditDocument(adjustments: [.exposure(ev: 0.2)]),
            EditDocument(adjustments: [.exposure(ev: 0.3)]),
        ]
        for (url, document) in zip(urls, documents) {
            try await store.save(document, for: EditSourceReference(assetID: .file(url), url: url))
        }

        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake, editStore: store)
        viewModel.collection.setSourceFolder(libraryFolder)
        try await waitUntil {
            viewModel.collection.items.count == urls.count
        }
        let firstIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == urls[0] })
        let thirdIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == urls[2] })
        viewModel.collection.select(at: firstIndex)
        viewModel.collection.select(at: thirdIndex, modifiers: [.command])

        let request = viewModel.selectedBatchExportRequest
        XCTAssertEqual(request.items.count, 2)
        XCTAssertEqual(
            Set(request.items.compactMap { $0.url?.lastPathComponent }),
            Set([urls[0].lastPathComponent, urls[2].lastPathComponent])
        )

        let outcome = await viewModel.export.performBatchExport(
            request.items,
            document: request.document,
            lut: request.lut,
            format: .png,
            to: try destinationFolder()
        )
        XCTAssertEqual(outcome, .init(exported: 2, failed: 0, total: 2))
        let requests = await fake.encodeRequests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.scale == .full })
        XCTAssertTrue(requests.contains { $0.document == documents[0] })
        XCTAssertTrue(requests.contains { $0.document == documents[2] })
        XCTAssertFalse(requests.contains { $0.document == documents[1] })
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
        XCTAssertEqual(
            ExportCoordinator.summary(
                for: .init(exported: 1, failed: 1, total: 4, cancelled: true), folder: folder
            ),
            "Export cancelled after 2 of 4 (1 exported, 1 failed, 2 not started) to Exports"
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
