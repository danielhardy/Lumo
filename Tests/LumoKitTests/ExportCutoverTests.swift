import XCTest
import CoreImage
import CoreGraphics
@testable import LumoKit

/// Phase 2 Step 6 — export renders the document.
///
/// The divergence this closes was real but unreachable: the preview reflected develop, adjustments,
/// the LUT and its intensity, while export reflected **only** the LUT and its intensity on a neutral
/// full-resolution decode. Nothing can set develop or adjustments until the Step 10 inspector, so no
/// user could see it — which is exactly the kind of gap that survives to the release where the
/// inspector lands.
///
/// Three kinds of test, deliberately:
///
/// - the **fake engine** pins what was asked to be encoded — which document, at which scale, in which
///   format, for which file — with no GPU and no disk;
/// - the **real engine** pins what actually lands on disk, compared against a graph built
///   independently rather than against the other half of the same pipeline. Parity alone cannot catch
///   preview and export being wrong *together*;
/// - and both **export paths** are covered, because `ExportCoordinator.performBatchExport` used to
///   load and grade each file itself. Cutting only the obvious one over would have left Export All on
///   the old behaviour with every parity test still green.
@MainActor
final class ExportCutoverTests: TempDirectoryTestCase {

    // MARK: - Fixtures

    private func makeImageFile(
        width: Int = 96, height: Int = 64, named name: String = "shot.png"
    ) throws -> URL {
        try Fixtures.writeGradientPNG(width: width, height: height, named: name, in: tempDirectory)
    }

    private func makeSource(named name: String = "shot.png") throws -> ImageSource {
        let url = try makeImageFile(named: name)
        return ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
    }

    private func destinationFolder(_ name: String = "out") throws -> URL {
        let folder = tempDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A document that exercises all three knobs at once, none of them at a value that is also the
    /// default. An intensity of 1.0 or an empty adjustment list would let a pipeline that ignored the
    /// document pass by accident.
    private func editedDocument(lut: CubeLUT) -> EditDocument {
        EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.75),
            adjustments: [.exposure(ev: 0.4), .vibrance(amount: 0.6)],
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.65)
        )
    }

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 10, _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func bytes(ofFileAt url: URL) throws -> [UInt8] {
        try Pixels.bytes(of: try Pixels.decode(try Data(contentsOf: url)))
    }

    /// Wait for a recorded request matching `predicate`.
    ///
    /// Several renders are in flight at once — the preview, the side-by-side baseline, the histogram
    /// — so "read the last request" silently reads whichever finished first. Match on the specific
    /// value you mean instead.
    private func awaitRequest(
        _ description: String,
        timeout: TimeInterval = 5,
        _ fetch: @escaping () async -> [FakeRenderEngine.Request],
        matching predicate: (FakeRenderEngine.Request) -> Bool
    ) async throws -> FakeRenderEngine.Request {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let match = await fetch().first(where: predicate) { return match }
            try await Task.sleep(for: .milliseconds(10))
        }
        let seen = await fetch()
        XCTFail("timed out waiting for \(description); saw \(seen.count) request(s): \(seen)")
        throw XCTSkip("no matching request")
    }

    private func awaitHistogramRequest(
        _ fake: FakeRenderEngine, _ description: String,
        matching predicate: (FakeRenderEngine.Request) -> Bool
    ) async throws -> FakeRenderEngine.Request {
        try await awaitRequest(description, { await fake.histogramRequests }, matching: predicate)
    }

    private func awaitPreviewRequest(
        _ fake: FakeRenderEngine, _ description: String,
        matching predicate: (FakeRenderEngine.Request) -> Bool
    ) async throws -> FakeRenderEngine.Request {
        try await awaitRequest(description, { await fake.previewRequests }, matching: predicate)
    }

    // MARK: - What the engine is asked to encode

    /// The whole document reaches the encoder, at full resolution, in the chosen format.
    func testTheDocumentReachesTheEncoderAtFullResolution() async throws {
        let fake = FakeRenderEngine()
        let coordinator = ExportCoordinator(engine: fake)
        // Not the default format: `.jpeg` is what a coordinator starts with, so asserting `.jpeg`
        // would pass against an encoder that ignored the picker entirely.
        coordinator.format = .tiff
        coordinator.onError = { XCTFail("unexpected error: \($0)") }

        let lut = TestImages.warmLUT()
        let document = editedDocument(lut: lut)
        let source = try makeSource()
        coordinator.performExport(
            source: source, document: document, lut: lut,
            to: tempDirectory.appendingPathComponent("out.tif")
        )
        try await waitUntil("the export to finish") { !coordinator.isExporting }

        let requests = await fake.encodeRequests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.document, document, "the whole document must reach the encoder")
        XCTAssertEqual(request.document.rawDevelop.exposure, 0.75, "develop must reach export")
        XCTAssertEqual(request.document.adjustments,
                       [.exposure(ev: 0.4), .vibrance(amount: 0.6)],
                       "adjustments must reach export, in order")
        XCTAssertEqual(request.document.lut.intensity, 0.65, "intensity must reach export")
        XCTAssertEqual(request.lutID, lut.lutID)
        XCTAssertEqual(request.scale, .full, "export must render at native resolution")
        XCTAssertEqual(request.format, .tiff)
        XCTAssertEqual(request.space, .current)
        XCTAssertEqual(request.source, source)
    }

    /// Batch export is the second path, and the one that is easy to miss. Every item must be encoded
    /// from the same document at `.full`, and each request must name *its own* file.
    func testBatchExportEncodesEveryItemFromTheSameDocument() async throws {
        let fake = FakeRenderEngine()
        let coordinator = ExportCoordinator(engine: fake)
        coordinator.format = .png
        coordinator.onError = { XCTFail("unexpected error: \($0)") }

        let lut = TestImages.warmLUT()
        let document = editedDocument(lut: lut)
        let urls = try ["a", "b", "c"].map { try makeImageFile(named: "\($0).png") }
        let items = zip(["a", "b", "c"], urls).map {
            ExportCoordinator.BatchItem(url: $1, data: nil, name: $0)
        }

        let outcome = await coordinator.performBatchExport(
            items, document: document, lut: lut, to: try destinationFolder()
        )
        XCTAssertEqual(outcome, .init(exported: 3, failed: 0, total: 3))

        let requests = await fake.encodeRequests
        XCTAssertEqual(requests.count, 3, "one encode per image")
        for request in requests {
            XCTAssertEqual(request.document, document,
                           "Export All must render the document, not just the LUT")
            XCTAssertEqual(request.scale, .full)
            XCTAssertEqual(request.format, .png)
        }
        // Matched on the source rather than by position: an off-by-one that encoded the same file
        // three times would still produce three requests carrying the right document.
        for url in urls {
            XCTAssertTrue(
                requests.contains { $0.source?.backing == .url(url) },
                "no encode request named \(url.lastPathComponent)"
            )
        }
    }

    // MARK: - What lands on disk

    /// The ship gate, at the pixels: an exported file must be the document rendered at native
    /// resolution.
    ///
    /// Compared against a graph built independently through `RenderPipeline`, **not** against the
    /// preview. Preview/export parity is asserted in `RenderEngineTests`, and on its own it cannot
    /// catch both halves being wrong together — the failure mode `docs/CODE_REVIEW.md` §5 names.
    func testExportedFileIsTheDocumentAtFullResolution() async throws {
        let coordinator = ExportCoordinator(engine: RenderEngine())
        coordinator.format = .png   // lossless: a JPEG comparison would be measuring the encoder
        coordinator.onError = { XCTFail("unexpected error: \($0)") }

        let lut = TestImages.warmLUT()
        let document = editedDocument(lut: lut)
        let source = try makeSource()
        let destination = tempDirectory.appendingPathComponent("graded.png")

        coordinator.performExport(source: source, document: document, lut: lut, to: destination)
        try await waitUntil("the export to finish") { !coordinator.isExporting }

        let written = try Pixels.decode(try Data(contentsOf: destination))
        XCTAssertEqual(written.width, 96, "export must be full resolution, not preview-sized")
        XCTAssertEqual(written.height, 64)

        let expected = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: document, lut: lut, scale: .full, space: .current
        ))
        assertPixelsEqual(try Pixels.bytes(of: written), try Pixels.bytes(of: expected),
                          "the exported file must be the document's own render")
    }

    /// And the document has to be *doing* something. An export that silently dropped develop and
    /// adjustments would still match a graph built from the same dropped document if the comparison
    /// above were the only check, so this pins that the edited export differs from the unedited one —
    /// and that each knob contributes.
    func testEachKnobVisiblyChangesTheExportedFile() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let source = try makeSource()

        func export(_ document: EditDocument, lut: CubeLUT?, named name: String) async throws -> [UInt8] {
            let coordinator = ExportCoordinator(engine: engine)
            coordinator.format = .png
            coordinator.onError = { XCTFail("unexpected error: \($0)") }
            let destination = tempDirectory.appendingPathComponent(name)
            coordinator.performExport(source: source, document: document, lut: lut, to: destination)
            try await waitUntil("\(name) to be written") { !coordinator.isExporting }
            return try bytes(ofFileAt: destination)
        }

        let plain = try await export(EditDocument(), lut: nil, named: "plain.png")
        let adjusted = try await export(
            EditDocument(adjustments: [.exposure(ev: 0.8)]), lut: nil, named: "adjusted.png"
        )
        let graded = try await export(
            EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1)), lut: lut, named: "graded.png"
        )
        let weakened = try await export(
            EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 0.3)), lut: lut, named: "weak.png"
        )

        assertPixelsDiffer(adjusted, plain, "an adjustment must change the exported file")
        assertPixelsDiffer(graded, plain, "the LUT must change the exported file")
        assertPixelsDiffer(weakened, graded, "intensity must change the exported file")
        assertPixelsDiffer(weakened, plain, "…without collapsing back to ungraded")
    }

    /// The same, through Export All. This is the trap: fixing only the single path leaves this
    /// writing a develop-less, adjustment-less render while every other test stays green.
    func testBatchExportWritesTheSameBytesAsTheSingleExport() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(
            adjustments: [.exposure(ev: 0.8), .vibrance(amount: 0.5)],
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.65)
        )
        let url = try makeImageFile(named: "subject.png")
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))

        // Single.
        let single = ExportCoordinator(engine: engine)
        single.format = .png
        single.onError = { XCTFail("unexpected error: \($0)") }
        let singleURL = tempDirectory.appendingPathComponent("single.png")
        single.performExport(source: source, document: document, lut: lut, to: singleURL)
        try await waitUntil("the single export") { !single.isExporting }

        // Batch, same document, and again with an empty one so "the document reached it" is
        // separable from "both paths agree".
        let batch = ExportCoordinator(engine: engine)
        batch.format = .png
        batch.onError = { XCTFail("unexpected error: \($0)") }
        let folder = try destinationFolder("batch")
        let items = [ExportCoordinator.BatchItem(url: url, data: nil, name: "subject")]
        _ = await batch.performBatchExport(items, document: document, lut: lut, to: folder)
        _ = await batch.performBatchExport(items, document: EditDocument(), lut: nil, to: folder)

        let batchGraded = try bytes(ofFileAt: folder.appendingPathComponent("subject_warm.png"))
        let batchPlain = try bytes(ofFileAt: folder.appendingPathComponent("subject.png"))

        assertPixelsEqual(batchGraded, try bytes(ofFileAt: singleURL),
                          "Export All must write what a single export writes")
        assertPixelsDiffer(batchGraded, batchPlain,
                           "Export All must honour the document, not just decode the file")
    }

    // MARK: - The view model hands over the right request

    /// `NSSavePanel` cannot run headless, so the assertion is on the request `exportDialog` builds.
    func testTheViewModelExportsTheEditedDocument() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        XCTAssertNil(viewModel.exportRequest, "nothing open means nothing to export")

        viewModel.openImage(url: try makeImageFile())
        try await waitUntil("the image to load") { viewModel.exportRequest != nil }

        let lut = TestImages.warmLUT()
        viewModel.selectLUT(lut)
        viewModel.updateDocument {
            $0.rawDevelop.exposure = 1.25
            $0.adjustments = [.vibrance(amount: 0.5)]
            $0.lut.intensity = 0.4
        }

        let request = try XCTUnwrap(viewModel.exportRequest)
        XCTAssertEqual(request.document, viewModel.document,
                       "⌘S must export the document that is on screen")
        XCTAssertEqual(request.document.rawDevelop.exposure, 1.25)
        XCTAssertEqual(request.document.adjustments, [.vibrance(amount: 0.5)])
        XCTAssertEqual(request.document.lut.intensity, 0.4)
        XCTAssertEqual(request.lut?.lutID, lut.lutID)
        XCTAssertEqual(request.baseName, "shot_warm")
    }

    /// Holding Space swaps the *preview*, not the file. Exporting the comparison baseline would drop
    /// the user's whole look the moment they compared before saving.
    func testHoldingSpaceDoesNotChangeWhatIsExported() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.openImage(url: try makeImageFile())
        try await waitUntil("the image to load") { viewModel.exportRequest != nil }

        let lut = TestImages.warmLUT()
        viewModel.selectLUT(lut)
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        viewModel.showOriginal(true)

        let request = try XCTUnwrap(viewModel.exportRequest)
        XCTAssertEqual(request.document.adjustments, [.exposure(ev: 0.5)],
                       "comparing must not strip adjustments from the export")
        XCTAssertEqual(request.lut?.lutID, lut.lutID, "…nor the LUT")
    }

    func testBatchExportRequestCarriesTheDocumentAndEveryItem() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        let files = try ["one", "two"].map { try makeImageFile(named: "\($0).png") }
        viewModel.collection.setSourceFolder(tempDirectory)
        try await waitUntil("the folder scan") { viewModel.collection.items.count >= files.count }

        let lut = TestImages.warmLUT()
        viewModel.selectLUT(lut)
        viewModel.updateDocument { $0.adjustments = [.vibrance(amount: 0.3)] }

        let request = viewModel.batchExportRequest
        XCTAssertEqual(request.document, viewModel.document)
        XCTAssertEqual(request.lut?.lutID, lut.lutID)
        // By filename: the scan hands back standardized URLs, so the temp directory's symlinked
        // `/var` → `/private/var` prefix makes a whole-URL comparison compare paths, not files.
        let scanned = Set(request.items.compactMap { $0.url?.lastPathComponent })
        for file in files {
            XCTAssertTrue(scanned.contains(file.lastPathComponent),
                          "\(file.lastPathComponent) missing from the batch; saw \(scanned)")
        }
    }

    // MARK: - The histogram came along

    /// Deleting `processedImage` took the histogram's source with it. It now renders the same
    /// document at the same scale as the preview — so an adjustment, which the old path could not
    /// see at all, has to move it.
    func testTheHistogramDescribesTheRenderedDocument() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        viewModel.openImage(url: try makeImageFile())
        try await waitUntil("the image to load") { viewModel.exportRequest != nil }

        viewModel.isInspectorPresented = true
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.9)] }

        // Match on the edited document rather than on "the last request": the opening render and the
        // adjusted one are both in flight, and a looser condition reads whichever landed first.
        let request = try await awaitHistogramRequest(fake, "the adjusted document") {
            $0.document.adjustments == [.exposure(ev: 0.9)]
        }
        guard case .preview(let box) = request.scale else {
            return XCTFail("the histogram should share the preview's scale, got \(request.scale)")
        }
        XCTAssertEqual(box, CGSize(width: 1600, height: 1200),
                       "a private scale would evict the developed-source memo every tally")
        XCTAssertEqual(request.space, .current)

        try await waitUntil("the histogram to be published") { viewModel.histogram != nil }
    }

    /// Nothing is tallied while the panel is closed — the reason the inspector gates it at all.
    func testNoHistogramIsRenderedWhileTheInspectorIsClosed() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        viewModel.openImage(url: try makeImageFile())
        try await waitUntil("the first preview") { viewModel.previewNSImage != nil }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.9)] }
        // Wait for the render the edit triggered, then give the histogram every chance to fire.
        _ = try await awaitPreviewRequest(fake, "the adjusted render") {
            $0.document.adjustments == [.exposure(ev: 0.9)]
        }
        try await Task.sleep(for: .milliseconds(150))

        let requests = await fake.histogramRequests
        XCTAssertTrue(requests.isEmpty, "the closed inspector should not be tallying pixels")
        XCTAssertNil(viewModel.histogram)
    }

    /// The real engine, end to end through the view model: the published histogram must actually
    /// change when the look does.
    func testThePublishedHistogramTracksTheDocument() async throws {
        let viewModel = AppViewModel(engine: RenderEngine())
        viewModel.openImage(url: try makeImageFile())
        try await waitUntil("the first preview") { viewModel.previewSurface.image != nil }

        viewModel.isInspectorPresented = true
        try await waitUntil("the first histogram") { viewModel.histogram != nil }
        let plain = try XCTUnwrap(viewModel.histogram)

        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 1.2)] }
        try await waitUntil("the adjusted histogram") { viewModel.histogram != plain }
        XCTAssertNotEqual(try XCTUnwrap(viewModel.histogram).red, plain.red,
                          "an adjustment must move the histogram the user is looking at")
    }
}
