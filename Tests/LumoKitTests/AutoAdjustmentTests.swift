import XCTest
@testable import LumoKit

@MainActor
final class AutoAdjustmentTests: TempDirectoryTestCase {
    private func histogram(
        luma: [(Int, Int)],
        red: [(Int, Int)]? = nil,
        green: [(Int, Int)]? = nil,
        blue: [(Int, Int)]? = nil
    ) -> HistogramData {
        func bins(_ values: [(Int, Int)]) -> [Int] {
            var result = [Int](repeating: 0, count: 256)
            for (level, count) in values { result[level] = count }
            return result
        }
        let channels = red ?? luma
        return HistogramData(
            red: bins(channels), green: bins(green ?? channels), blue: bins(blue ?? channels),
            luma: bins(luma)
        )
    }

    func testRepresentativeFixturesProduceFiniteBoundedAndStableResults() {
        let fixtures: [HistogramData] = [
            // Neutral, clipped, low-key, high-contrast, and color-biased representatives.
            histogram(luma: [(128, 100)]),
            histogram(luma: [(0, 20), (128, 60), (255, 20)]),
            histogram(luma: [(24, 60), (48, 40)]),
            histogram(luma: [(0, 50), (255, 50)]),
            histogram(luma: [(80, 100)], red: [(240, 100)], green: [(55, 100)], blue: [(35, 100)])
        ]

        for fixture in fixtures {
            guard let first = AutoAdjustmentAnalyzer.analyze(histogram: fixture),
                  let second = AutoAdjustmentAnalyzer.analyze(histogram: fixture) else {
                return XCTFail("representative histogram should be actionable")
            }
            XCTAssertEqual(first, second, "Auto must be deterministic for one analyzed input")
            XCTAssertTrue(first.light.exposure.isFinite)
            XCTAssertTrue(first.light.contrast.isFinite)
            XCTAssertTrue(first.light.highlights.isFinite)
            XCTAssertTrue(first.light.shadows.isFinite)
            XCTAssertTrue(first.light.whites.isFinite)
            XCTAssertTrue(first.light.blacks.isFinite)
            XCTAssertTrue(first.color.vibrance.isFinite)
            XCTAssertTrue(first.color.saturation.isFinite)
            XCTAssertTrue(LightAdjustments.exposureRange.contains(first.light.exposure))
            XCTAssertTrue(LightAdjustments.contrastRange.contains(first.light.contrast))
            XCTAssertTrue(LightAdjustments.highlightsRange.contains(first.light.highlights))
            XCTAssertTrue(LightAdjustments.shadowsRange.contains(first.light.shadows))
            XCTAssertTrue(LightAdjustments.whitesRange.contains(first.light.whites))
            XCTAssertTrue(LightAdjustments.blacksRange.contains(first.light.blacks))
            XCTAssertTrue(ColorAdjustments.vibranceRange.contains(first.color.vibrance))
            XCTAssertTrue(ColorAdjustments.saturationRange.contains(first.color.saturation))
        }
    }

    func testHeuristicRespondsConservativelyToLowKeyClippingAndColorBias() {
        let lowKey = AutoAdjustmentAnalyzer.analyze(
            histogram: histogram(luma: [(24, 60), (48, 40)])
        )!
        XCTAssertGreaterThan(lowKey.light.exposure, 0)
        XCTAssertGreaterThan(lowKey.light.shadows, 0)

        let clipped = AutoAdjustmentAnalyzer.analyze(
            histogram: histogram(
                luma: [(0, 20), (128, 60), (255, 20)],
                red: [(255, 70), (100, 30)], green: [(120, 100)], blue: [(100, 100)]
            )
        )!
        XCTAssertLessThan(clipped.light.highlights, 0)
        XCTAssertGreaterThan(clipped.light.shadows, 0)
        XCTAssertLessThan(clipped.color.saturation, 0)

        let highContrast = AutoAdjustmentAnalyzer.analyze(
            histogram: histogram(luma: [(0, 50), (255, 50)])
        )!
        XCTAssertLessThanOrEqual(highContrast.light.contrast, 0)
    }

    func testMalformedOrEmptyHistogramDoesNotProduceAnEdit() {
        let empty = HistogramData(
            red: [Int](repeating: 0, count: 256),
            green: [Int](repeating: 0, count: 256),
            blue: [Int](repeating: 0, count: 256),
            luma: [Int](repeating: 0, count: 256)
        )
        XCTAssertNil(AutoAdjustmentAnalyzer.analyze(histogram: empty))
        XCTAssertNil(AutoAdjustmentAnalyzer.analyze(
            histogram: HistogramData(red: [0], green: [0], blue: [0], luma: [0])
        ))
    }

    private func openStandardImage(_ viewModel: AppViewModel) async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "auto.png", in: tempDirectory
        )
        viewModel.openImage(url: url)
        let deadline = Date().addingTimeInterval(5)
        while viewModel.previewState != .ready {
            if Date() > deadline { return XCTFail("timed out waiting for the preview") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testActionIsUnavailableBeforeASettledSupportedPhoto() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        XCTAssertFalse(viewModel.canRunAutoAdjustment)
        XCTAssertFalse(viewModel.isAutoAdjustmentInProgress)
        XCTAssertTrue(viewModel.autoAdjustmentHelp.contains("supported photo"))
    }

    func testAutoReplacesOnlyGlobalLightAndColorAsOneUndoableOperation() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        viewModel.updateDocument {
            $0.rawDevelop.exposure = 0.4
            $0.light.exposure = 1
            $0.color.saturation = 20
            $0.color.mixer.blue.saturation = 15
            $0.adjustments = [.exposure(ev: 0.5)]
            $0.effects.vignette.amount = 10
            $0.crop = CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
        }
        let before = viewModel.document
        let depthBefore = viewModel.undoDepth

        viewModel.runAutoAdjustment()
        let deadline = Date().addingTimeInterval(5)
        while !viewModel.statusMessage.hasPrefix("Auto applied") {
            if Date() > deadline { return XCTFail("timed out waiting for Auto") }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(viewModel.undoDepth, depthBefore + 1)
        XCTAssertEqual(viewModel.document.rawDevelop, before.rawDevelop)
        XCTAssertEqual(viewModel.document.adjustments, before.adjustments)
        XCTAssertEqual(viewModel.document.effects, before.effects)
        XCTAssertEqual(viewModel.document.crop, before.crop)
        XCTAssertEqual(viewModel.document.color.mixer, before.color.mixer)
        XCTAssertNotEqual(viewModel.document.light, before.light)

        viewModel.undo()
        XCTAssertEqual(viewModel.document, before, "one undo must restore the complete prior document")
    }

    func testFailureLeavesAutoAndHistogramOutOfLoadingState() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        await fake.setShouldFailHistogram(true)

        viewModel.runAutoAdjustment()
        let deadline = Date().addingTimeInterval(5)
        while !viewModel.autoAdjustmentHelp.contains("could not analyze") {
            if Date() > deadline { return XCTFail("timed out waiting for Auto failure") }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(viewModel.isAutoAdjustmentInProgress)
        XCTAssertFalse(viewModel.isHistogramLoading)
    }

    func testAnalysisShowsProgressWithoutBorrowingHistogramLoadingState() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        await fake.gateHistogram()

        viewModel.runAutoAdjustment()
        let deadline = Date().addingTimeInterval(5)
        while !viewModel.isAutoAdjustmentInProgress {
            if Date() > deadline { return XCTFail("timed out waiting for Auto analysis state") }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(viewModel.isHistogramLoading)
        XCTAssertTrue(viewModel.autoAdjustmentHelp.contains("Analyzing"))

        await fake.releaseHistograms()
        while viewModel.isAutoAdjustmentInProgress {
            if Date() > deadline { return XCTFail("timed out waiting for Auto completion") }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(viewModel.statusMessage.hasPrefix("Auto applied"))
        let requests = await fake.histogramRequests
        XCTAssertEqual(requests.last?.lutID, nil)
        XCTAssertTrue(requests.last?.document.light.isIdentity == true)
        XCTAssertEqual(requests.last?.document.color.vibrance, 0)
        XCTAssertEqual(requests.last?.document.color.saturation, 0)
    }

    func testRepeatingAutoIsDeterministicAndDoesNotAddAnotherHistoryEntry() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        viewModel.runAutoAdjustment()
        let deadline = Date().addingTimeInterval(5)
        while !viewModel.statusMessage.hasPrefix("Auto applied") {
            if Date() > deadline { return XCTFail("timed out waiting for first Auto") }
            try await Task.sleep(for: .milliseconds(10))
        }
        let first = viewModel.document
        let depth = viewModel.undoDepth

        viewModel.runAutoAdjustment()
        while !viewModel.statusMessage.hasPrefix("Auto applied") {
            if Date() > deadline { return XCTFail("timed out waiting for repeated Auto") }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(viewModel.document, first)
        XCTAssertEqual(viewModel.undoDepth, depth)
    }
}
