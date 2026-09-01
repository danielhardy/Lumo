import CoreGraphics
import CoreImage
import XCTest
@testable import LumoKit

final class CropModelTests: XCTestCase {
    func testCropIsNormalizedBoundedAndCodable() throws {
        let crop = CropAdjustments(normalizedRect: CGRect(x: -0.1, y: 0.2, width: 0.8, height: 0.9))
        let rect = try XCTUnwrap(crop.normalizedRect)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.000001)
        XCTAssertEqual(rect.minY, 0.2, accuracy: 0.000001)
        XCTAssertEqual(rect.width, 0.7, accuracy: 0.000001)
        XCTAssertEqual(rect.height, 0.8, accuracy: 0.000001)
        XCTAssertFalse(crop.isIdentity)

        let document = EditDocument(crop: crop)
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(EditDocument.self, from: data), document)
    }

    func testMissingCropFieldKeepsLegacyDocumentsNeutral() throws {
        let document = try JSONDecoder().decode(EditDocument.self, from: Data("{\"version\":1}".utf8))
        XCTAssertEqual(document.crop, .neutral)
        XCTAssertTrue(document.isIdentity)
    }

    func testCropIsCopiedSelectivelyAndComparisonKeepsItsFrame() {
        let crop = CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        let document = EditDocument(crop: crop, adjustments: [.exposure(ev: 0.5)])
        let clipboard = EditClipboardPayload(document: document)
        XCTAssertEqual(clipboard.crop.normalizedRect, crop.normalizedRect)

        let result = clipboard.applying(
            to: EditDocument(), destinationIsRAW: false, categories: [.crop]
        )
        XCTAssertEqual(result.crop, crop)
        XCTAssertEqual(document.comparisonBaseline.crop, crop)
        XCTAssertTrue(document.hasVisibleLookEdits)
    }

    func testCropClampingRejectsDegenerateInput() {
        XCTAssertEqual(CropAdjustments(normalizedRect: CGRect(x: 0, y: 0, width: 0, height: 1)), .neutral)
        XCTAssertEqual(CropAdjustments(normalizedRect: nil), .neutral)
    }
}

final class CropPipelineTests: TempDirectoryTestCase {
    private var source: ImageSource!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "crop.png", in: tempDirectory)
        source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
    }

    func testNormalizedCropChangesExtentWithoutRasterizingTheGraph() throws {
        let input = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(
            to: CGRect(x: 10, y: 20, width: 80, height: 40)
        )
        let result = RenderPipeline.applyCrop(
            CropAdjustments(normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)),
            to: input
        )
        XCTAssertEqual(result.extent, CGRect(x: 30, y: 30, width: 40, height: 20))
    }

    func testPreviewAndFullResolutionExportUseTheSameCropExtentAndPixels() async throws {
        let engine = RenderEngine()
        let document = EditDocument(
            effects: EffectsAdjustments(vignette: VignetteAdjustments(amount: 45)),
            crop: CropAdjustments(normalizedRect: CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.75))
        )
        let rendered = await engine.makeCGImage(
            source: source, document: document, lut: nil, scale: .full, space: .current
        )
        let preview: CGImage = try XCTUnwrap(rendered)
        let exported = try await engine.encode(
            source: source, document: document, lut: nil, scale: .full,
            format: .png, quality: 1, space: .current
        )
        let decoded = try Pixels.decode(exported)

        XCTAssertEqual(preview.width, 48)
        XCTAssertEqual(preview.height, 48)
        XCTAssertEqual(decoded.width, preview.width)
        XCTAssertEqual(decoded.height, preview.height)
        assertPixelsEqual(try Pixels.bytes(of: preview), try Pixels.bytes(of: decoded),
                          "preview and export must retain crop and post-crop effects identically")
    }
}

@MainActor
final class CropWorkflowTests: TempDirectoryTestCase {
    private func waitUntil(_ description: String, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for (description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A bounded wait for the fake engine's actor-isolated request log, mirroring `waitUntil`'s
    /// deadline so a regression (a call site that stops asking for a render) fails the assertion
    /// below instead of hanging the test run.
    private func waitUntilRequestCount(exceeds count: Int, on engine: FakeRenderEngine) async throws {
        let deadline = Date().addingTimeInterval(5)
        while await engine.previewRequests.count <= count {
            if Date() > deadline {
                return XCTFail("timed out waiting for a new render request")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testDraftIsTransientCancelIsFreeAndCommitIsUndoable() async throws {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "workflow.png", in: tempDirectory)
        let viewModel = AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(fileURL: tempDirectory.appendingPathComponent("edits.json"))
        )
        viewModel.openImage(url: url)
        try await waitUntil("the source image") { viewModel.sourceImage != nil }

        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        XCTAssertTrue(viewModel.isCropToolActive)
        XCTAssertTrue(viewModel.document.crop.isIdentity, "a draft must not change the document")
        viewModel.cancelCrop()
        XCTAssertFalse(viewModel.isCropToolActive)
        XCTAssertTrue(viewModel.document.crop.isIdentity)
        XCTAssertEqual(viewModel.undoDepth, 0)

        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        viewModel.commitCrop()
        let committed = CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        XCTAssertEqual(viewModel.document.crop, committed)
        XCTAssertEqual(viewModel.undoDepth, 1)

        viewModel.undo()
        XCTAssertTrue(viewModel.document.crop.isIdentity)
        viewModel.redo()
        XCTAssertEqual(viewModel.document.crop, committed)
    }

    /// Covers the LUMO-115 fix directly: while Crop is open, the pixels under the full-source
    /// overlay must come from the same adjusted stage with the composition crop stripped, not the
    /// already-cropped committed render. Asserting on the render *request* handed to the engine
    /// (rather than only `document.crop`) is what the issue's verification plan means by testing
    /// geometry/UI behavior instead of only the normalized rectangle.
    func testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit() async throws {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "reentry.png", in: tempDirectory)
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(
            engine: fake,
            editStore: EditDocumentStore(fileURL: tempDirectory.appendingPathComponent("edits.json"))
        )
        viewModel.openImage(url: url)
        try await waitUntil("the source image") { viewModel.sourceImage != nil }

        let committedRect = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        viewModel.beginCrop()
        viewModel.updateCropDraft(committedRect)
        viewModel.commitCrop()
        let committed = CropAdjustments(normalizedRect: committedRect)
        XCTAssertEqual(viewModel.document.crop, committed)

        let requestsBeforeReentry = await fake.previewRequests.count
        viewModel.beginCrop()
        try await waitUntilRequestCount(exceeds: requestsBeforeReentry, on: fake)
        let reentryRequests = await fake.previewRequests
        let reentryRequest = try XCTUnwrap(reentryRequests.last)
        XCTAssertTrue(
            reentryRequest.document.crop.isIdentity,
            "reopening Crop must render the full source stage, not the already-cropped committed frame"
        )
        XCTAssertEqual(viewModel.document.crop, committed, "the committed document must be untouched while editing")

        let requestsBeforeCancel = await fake.previewRequests.count
        viewModel.cancelCrop()
        try await waitUntilRequestCount(exceeds: requestsBeforeCancel, on: fake)
        let cancelRequests = await fake.previewRequests
        let cancelRequest = try XCTUnwrap(cancelRequests.last)
        XCTAssertEqual(
            cancelRequest.document.crop, committed,
            "Cancel must restore the committed framing under the overlay"
        )
    }

    func testCommittedCropSurvivesRelaunch() async throws {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "persisted.png", in: tempDirectory)
        let storeURL = tempDirectory.appendingPathComponent("persisted-edits.json")
        let first = AppViewModel(engine: FakeRenderEngine(), editStore: EditDocumentStore(fileURL: storeURL))
        first.openImage(url: url)
        try await waitUntil("the first source") { first.sourceImage != nil }
        first.beginCrop()
        first.updateCropDraft(CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8))
        first.commitCrop()
        await first.flushPendingWrites()

        let second = AppViewModel(engine: FakeRenderEngine(), editStore: EditDocumentStore(fileURL: storeURL))
        second.openImage(url: url)
        try await waitUntil("the restored crop") {
            second.sourceImage != nil && second.document.crop == CropAdjustments(
                normalizedRect: CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)
            )
        }
    }
}
