import XCTest
@testable import LumoKit

@MainActor
final class EffectsInspectorTests: TempDirectoryTestCase {

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
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "effects.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
    }

    func testEveryControlMapsItsOwnValueAndKeepsSiblingValues() {
        var effects = EffectsAdjustments(
            texture: 12, clarity: -20, dehaze: 34,
            vignette: VignetteAdjustments(amount: 50, midpoint: 42),
            grain: GrainAdjustments(amount: 30, size: 22)
        )

        for control in EffectsControl.allCases {
            let value: Double = control == .texture ? 71 : control == .clarity ? -63 : 48
            effects = control.setting(value, in: effects)
            XCTAssertEqual(control.value(in: effects), value)
        }
        for control in VignetteControl.allCases {
            effects.vignette = control.setting(control.neutral, in: effects.vignette)
            XCTAssertEqual(control.value(in: effects.vignette), control.neutral)
        }
        for control in GrainControl.allCases {
            effects.grain = control.setting(control.neutral, in: effects.grain)
            XCTAssertEqual(control.value(in: effects.grain), control.neutral)
        }

        XCTAssertEqual(effects.texture, 71)
        XCTAssertEqual(effects.clarity, -63)
        XCTAssertEqual(effects.dehaze, 48)
    }

    func testBindingsRoundTripAndIndividualResetsPreserveOtherEffects() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.effectsBinding(for: .texture).wrappedValue = 72.5
        viewModel.effectsBinding(for: .clarity).wrappedValue = -18
        viewModel.vignetteBinding(for: .amount).wrappedValue = 65
        viewModel.vignetteBinding(for: .midpoint).wrappedValue = 40
        viewModel.grainBinding(for: .amount).wrappedValue = 55
        viewModel.grainBinding(for: .size).wrappedValue = 24

        XCTAssertEqual(viewModel.effectsValue(for: .texture), 72.5, accuracy: 1e-12)
        XCTAssertEqual(viewModel.effectsValue(for: .clarity), -18, accuracy: 1e-12)
        XCTAssertEqual(viewModel.vignetteValue(for: .amount), 65, accuracy: 1e-12)
        XCTAssertEqual(viewModel.grainValue(for: .size), 24, accuracy: 1e-12)
        XCTAssertTrue(viewModel.hasEffects)

        viewModel.resetVignette(.amount)
        viewModel.resetGrain(.amount)
        viewModel.resetEffects(.texture)

        XCTAssertEqual(viewModel.effectsValue(for: .texture), 0)
        XCTAssertEqual(viewModel.effectsValue(for: .clarity), -18)
        XCTAssertEqual(viewModel.vignetteValue(for: .amount), 0)
        XCTAssertEqual(viewModel.vignetteValue(for: .midpoint), 40)
        XCTAssertEqual(viewModel.grainValue(for: .amount), 0)
        XCTAssertEqual(viewModel.grainValue(for: .size), 24)
        XCTAssertTrue(viewModel.hasEffects)
    }

    func testRetainedSubordinateValuesKeepEffectsResettableAtZeroAmount() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.vignetteBinding(for: .midpoint).wrappedValue = 30
        viewModel.grainBinding(for: .size).wrappedValue = 20

        XCTAssertTrue(viewModel.document.effects.isIdentity,
                      "the render remains identity while both amount gates are off")
        XCTAssertTrue(viewModel.hasEffects,
                      "the retained recipe still needs a reset affordance")
        XCTAssertTrue(viewModel.hasVignetteAdjustments)
        XCTAssertTrue(viewModel.hasGrainAdjustments)

        viewModel.resetAllVignette()
        viewModel.resetAllGrain()
        XCTAssertFalse(viewModel.hasEffects)
        XCTAssertEqual(viewModel.document.effects, .neutral)
    }

    func testResetAllEffectsIsIsolatedFromOtherPanels() async throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.effectsBinding(for: .dehaze).wrappedValue = 60
        viewModel.lightBinding(for: .exposure).wrappedValue = 1
        viewModel.resetAllEffects()

        XCTAssertTrue(viewModel.document.effects.isIdentity)
        XCTAssertEqual(viewModel.document.light.exposure, 1)
    }

    func testSliderGestureUsesInteractiveRenderingAndOneUndoEntry() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        let atRest = await fake.previewRequests.count

        viewModel.beginPreviewInteraction()
        for value in stride(from: 0.0, through: 70.0, by: 5.0) {
            viewModel.effectsBinding(for: .clarity).wrappedValue = value
        }
        viewModel.endPreviewInteraction()

        try await waitUntil("the settled Effects render") {
            await fake.previewRequests.contains { $0.document.effects.clarity == 70 }
        }
        let issued = await fake.previewRequests.count - atRest
        XCTAssertLessThan(issued, 10, "interactive Effects edits should be coalesced")

        viewModel.undo()
        XCTAssertEqual(viewModel.effectsValue(for: .clarity), 0,
                       "one completed gesture should undo as one edit")
        XCTAssertTrue(viewModel.canRedo)
        viewModel.redo()
        XCTAssertEqual(viewModel.effectsValue(for: .clarity), 70)
    }

    func testEffectsDocumentRoundTripsAsCopyableValue() throws {
        let document = EditDocument(effects: EffectsAdjustments(
            texture: 30, clarity: -12, dehaze: 55,
            vignette: VignetteAdjustments(amount: 70, midpoint: 35, roundness: -20, feather: 80, highlights: 45),
            grain: GrainAdjustments(amount: 65, size: 25, roughness: 85)
        ))
        let data = try JSONEncoder().encode(document)
        let copy = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(copy, document)
        XCTAssertNotEqual(copy.editHash, EditDocument().editHash)
    }
}
