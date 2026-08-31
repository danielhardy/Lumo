import XCTest
@testable import LumoKit

@MainActor
final class ColorInspectorTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func openStandardImage(_ viewModel: AppViewModel) async throws {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "color.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
    }

    func testColorControlsRoundTripThroughBindingsWithoutDrift() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.colorBinding(for: .vibrance).wrappedValue = 37.5
        viewModel.colorBinding(for: .saturation).wrappedValue = -42.25

        XCTAssertEqual(viewModel.colorValue(for: .vibrance), 37.5, accuracy: 1e-12)
        XCTAssertEqual(viewModel.colorValue(for: .saturation), -42.25, accuracy: 1e-12)
        XCTAssertEqual(viewModel.document.color.vibrance, 37.5, accuracy: 1e-12)
        XCTAssertEqual(viewModel.document.color.saturation, -42.25, accuracy: 1e-12)
    }

    func testMixerAndGradingBindingsEditOnlyTheirNestedValues() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.mixerBinding(for: .blue, control: .hue).wrappedValue = -18
        viewModel.mixerBinding(for: .blue, control: .luminance).wrappedValue = 23
        viewModel.gradingBinding(for: .shadows, control: .hue).wrappedValue = 220
        viewModel.gradingBinding(for: .shadows, control: .saturation).wrappedValue = 40
        viewModel.gradingGlobalBinding(for: .balance).wrappedValue = -15

        XCTAssertEqual(viewModel.mixerChannelValue(.blue), ColorMixerChannel(hue: -18, luminance: 23))
        XCTAssertEqual(viewModel.mixerChannelValue(.red), .neutral)
        XCTAssertEqual(viewModel.gradingWheelValue(.shadows), ColorGradingWheel(hue: 220, saturation: 40))
        XCTAssertEqual(viewModel.gradingWheelValue(.highlights), .neutral)
        XCTAssertEqual(viewModel.gradingGlobalValue(for: .balance), -15, accuracy: 1e-12)
    }

    func testSectionResetsPreserveOtherColorSections() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.colorBinding(for: .vibrance).wrappedValue = 25
        viewModel.mixerBinding(for: .green, control: .saturation).wrappedValue = 45
        viewModel.gradingBinding(for: .highlights, control: .saturation).wrappedValue = 35
        viewModel.adjustmentBinding(for: .temperature).wrappedValue = 9000
        viewModel.adjustmentBinding(for: .tint).wrappedValue = 18

        viewModel.resetAllMixer()
        viewModel.resetAllGrading()
        viewModel.resetAllColor()

        XCTAssertTrue(viewModel.document.color.isIdentity)
        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), 9000, accuracy: 1e-12)
        XCTAssertEqual(viewModel.adjustmentValue(for: .tint), 18, accuracy: 1e-12)
        XCTAssertFalse(viewModel.document.adjustments.isEmpty)
    }

    func testRowResetsPreserveSiblingMixerAndGradingValues() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.mixerBinding(for: .red, control: .hue).wrappedValue = 20
        viewModel.mixerBinding(for: .red, control: .saturation).wrappedValue = 45
        viewModel.gradingBinding(for: .midtones, control: .hue).wrappedValue = 120
        viewModel.gradingBinding(for: .midtones, control: .saturation).wrappedValue = 30

        viewModel.resetMixer(.red, .hue)
        viewModel.resetGrading(.midtones, .saturation)

        XCTAssertEqual(viewModel.mixerChannelValue(.red), ColorMixerChannel(saturation: 45))
        XCTAssertEqual(viewModel.gradingWheelValue(.midtones), ColorGradingWheel(hue: 120))
    }

    func testColorSliderUsesInteractiveRenderAndSettlesLatestValue() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        let atRest = await fake.previewRequests.count

        viewModel.beginPreviewInteraction()
        for value in stride(from: 0.0, through: 50.0, by: 5.0) {
            viewModel.colorBinding(for: .vibrance).wrappedValue = value
        }
        viewModel.endPreviewInteraction()

        try await waitUntil("the settled color render") {
            await fake.previewRequests.contains { $0.document.color.vibrance == 50 }
        }
        let issued = await fake.previewRequests.count - atRest
        XCTAssertLessThan(issued, 8, "interactive color edits should be coalesced")
    }

    func testWhiteBalanceResetRestoresBothRowsAsOneNeutralOperation() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .temperature).wrappedValue = 9000
        viewModel.adjustmentBinding(for: .tint).wrappedValue = 22
        XCTAssertTrue(viewModel.hasWhiteBalanceAdjustments)

        viewModel.resetWhiteBalance()

        XCTAssertFalse(viewModel.hasWhiteBalanceAdjustments)
        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), AdjustmentControl.temperature.neutral)
        XCTAssertEqual(viewModel.adjustmentValue(for: .tint), AdjustmentControl.tint.neutral)
    }
}
