import XCTest
@testable import LumoKit

@MainActor
final class LightInspectorTests: TempDirectoryTestCase {
    func testLightControlsExposePhotographerRangesInPanelOrder() {
        XCTAssertEqual(LightControl.allCases, [.exposure, .contrast, .highlights, .shadows, .whites, .blacks])
        XCTAssertEqual(LightControl.exposure.range, -5...5)
        XCTAssertEqual(LightControl.contrast.range, -100...100)
        XCTAssertEqual(LightControl.highlights.range, -100...100)
        XCTAssertEqual(LightControl.shadows.range, -100...100)
        XCTAssertEqual(LightControl.whites.range, -100...100)
        XCTAssertEqual(LightControl.blacks.range, -100...100)
        XCTAssertEqual(LightControl.allCases.map(\.title), [
            "Exposure", "Contrast", "Highlights", "Shadows", "Whites", "Blacks"
        ])
    }

    func testLightBindingRoundTripsAndDoesNotTouchOtherDocumentSections() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument {
            $0.rawDevelop.exposure = 0.25
            $0.adjustments = [.exposure(ev: 0.5)]
            $0.lut.intensity = 0.4
        }

        viewModel.lightBinding(for: .highlights).wrappedValue = 42

        XCTAssertEqual(viewModel.lightValue(for: .highlights), 42)
        XCTAssertEqual(viewModel.document.rawDevelop.exposure, 0.25)
        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.5)])
        XCTAssertEqual(viewModel.document.lut.intensity, 0.4)
    }

    func testIndividualAndPanelResetsAreScopedAndUndoable() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument {
            $0.light.exposure = 1
            $0.light.whites = 20
            $0.adjustments = [.exposure(ev: 0.5)]
        }

        viewModel.resetLight(.exposure)
        XCTAssertEqual(viewModel.document.light.exposure, 0)
        XCTAssertEqual(viewModel.document.light.whites, 20)
        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.5)])
        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.exposure, 1)
        XCTAssertEqual(viewModel.document.light.whites, 20)

        viewModel.resetAllLight()
        XCTAssertTrue(viewModel.document.light.isIdentity)
        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.5)])
        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.exposure, 1)
        XCTAssertEqual(viewModel.document.light.whites, 20)
    }

    func testLightSliderGestureIsOneUndoOperation() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.beginPreviewInteraction()
        for value in stride(from: 0.1, through: 0.8, by: 0.1) {
            viewModel.lightBinding(for: .exposure).wrappedValue = value
        }
        viewModel.endPreviewInteraction()

        XCTAssertEqual(viewModel.document.light.exposure, 0.8, accuracy: 0.000_001)
        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.exposure, 0, accuracy: 0.000_001)
        XCTAssertFalse(viewModel.canUndo)
        viewModel.redo()
        XCTAssertEqual(viewModel.document.light.exposure, 0.8, accuracy: 0.000_001)
    }

    func testComparisonBaselineRemovesLightButKeepsDevelop() {
        let document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.5),
            light: LightAdjustments(exposure: 1),
            color: ColorAdjustments(vibrance: 25)
        )
        XCTAssertTrue(document.originalForComparison.light.isIdentity)
        XCTAssertTrue(document.originalForComparison.color.isIdentity)
        XCTAssertEqual(document.originalForComparison.rawDevelop.exposure, 0.5)
        XCTAssertTrue(document.originalForComparison.adjustments.isEmpty)
        XCTAssertTrue(document.originalForComparison.lut.isIdentity)
    }

    func testPhotoHandoffRestoresTheLightDocumentAndHistory() async throws {
        let first = try Fixtures.writeGradientPNG(width: 16, height: 12, named: "first.png", in: tempDirectory)
        let second = try Fixtures.writeGradientPNG(width: 16, height: 12, named: "second.png", in: tempDirectory)
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.openImage(url: first)
        try await waitUntil { viewModel.sourceName == "first.png" }
        viewModel.updateDocument { $0.light.exposure = 1.25 }

        viewModel.openImage(url: second)
        try await waitUntil { viewModel.sourceName == "second.png" }
        XCTAssertTrue(viewModel.document.light.isIdentity)

        viewModel.openImage(url: first)
        try await waitUntil { viewModel.sourceName == "first.png" }
        XCTAssertEqual(viewModel.document.light.exposure, 1.25)
        viewModel.undo()
        XCTAssertTrue(viewModel.document.light.isIdentity)
    }

    func testAccessibilityAdjustableActionAddsTheFirstCurvePoint() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        XCTAssertTrue(viewModel.document.light.toneCurve.points.dropFirst().dropLast().isEmpty)

        let synthetic = LightCurvePoint(input: 0.5, output: viewModel.document.light.toneCurve.value(at: 0.5))
        viewModel.setToneCurvePoint(synthetic, output: synthetic.output + 0.01)

        let interior = viewModel.document.light.toneCurve.points.dropFirst().dropLast()
        XCTAssertEqual(interior.count, 1)
        XCTAssertEqual(interior.first?.output ?? -1, synthetic.output + 0.01, accuracy: 0.000_001)
    }

    func testCurveAddAndRemoveEachUseOneUndoStep() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.addToneCurvePoint(input: 0.25)
        XCTAssertEqual(
            viewModel.document.light.toneCurve.value(at: 0.25), 0.25, accuracy: 0.000_001
        )

        viewModel.removeToneCurvePoint(atInput: 0.25)
        XCTAssertTrue(viewModel.document.light.toneCurve.isIdentity)

        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.toneCurve.points.dropFirst().dropLast().count, 1)
        viewModel.undo()
        XCTAssertTrue(viewModel.document.light.toneCurve.isIdentity)
    }

    func testCurveDragCoalescesEveryTickIntoOneUndoStep() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.beginPreviewInteraction()

        for output in [0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85] {
            viewModel.moveToneCurvePoint(fromInput: 0.5, input: 0.5, output: output)
        }
        viewModel.endPreviewInteraction()

        XCTAssertEqual(
            viewModel.document.light.toneCurve.value(at: 0.5), 0.85, accuracy: 0.000_001
        )
        viewModel.undo()
        XCTAssertTrue(viewModel.document.light.toneCurve.isIdentity,
                      "all curve drag ticks should undo as one gesture")
        XCTAssertFalse(viewModel.canUndo)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for image load") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
