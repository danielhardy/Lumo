import XCTest
@testable import LumoKit

@MainActor
final class ResettableInspectorTests: XCTestCase {
    func testRepresentativeRowsResetToTheirNeutralValues() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument { document in
            document.rawDevelop.exposure = 1.2
            document.light = LightAdjustments(exposure: 1.25, shadows: 30)
            document.adjustments = [
                .exposure(ev: 0.5),
                .colorControls(brightness: 0.2, contrast: 1.5, saturation: 0.6),
                .temperatureTint(temp: 4200, tint: 25),
            ]
            document.color = ColorAdjustments(
                vibrance: 35,
                saturation: -20,
                mixer: ColorMixerAdjustments(
                    red: ColorMixerChannel(hue: 24, saturation: 35, luminance: -12)
                ),
                grading: ColorGradingAdjustments(
                    midtones: ColorGradingWheel(hue: 120, saturation: 40),
                    blending: 70,
                    balance: -20
                )
            )
            document.effects = EffectsAdjustments(
                texture: 22,
                clarity: -18,
                vignette: VignetteAdjustments(amount: 60, midpoint: 42),
                grain: GrainAdjustments(amount: 50, size: 20, roughness: 70)
            )
        }

        viewModel.resetDevelop(.exposure)
        XCTAssertNil(viewModel.document.rawDevelop.exposure)

        viewModel.resetLight(.shadows)
        XCTAssertEqual(viewModel.lightValue(for: .shadows), LightControl.shadows.neutral)
        XCTAssertEqual(viewModel.lightValue(for: .exposure), 1.25)

        viewModel.resetAdjustment(.contrast)
        XCTAssertEqual(viewModel.adjustmentValue(for: .contrast), AdjustmentControl.contrast.neutral)
        XCTAssertEqual(viewModel.adjustmentValue(for: .saturation), 0.6)

        viewModel.resetWhiteBalance(.temperature)
        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), AdjustmentControl.temperature.neutral)
        XCTAssertEqual(viewModel.adjustmentValue(for: .tint), 25)
        viewModel.resetWhiteBalance(.tint)
        XCTAssertEqual(viewModel.adjustmentValue(for: .tint), AdjustmentControl.tint.neutral)

        viewModel.resetColor(.vibrance)
        XCTAssertEqual(viewModel.colorValue(for: .vibrance), 0)
        XCTAssertEqual(viewModel.colorValue(for: .saturation), -20)

        viewModel.resetMixer(.red, .hue)
        XCTAssertEqual(viewModel.mixerValue(for: .red, control: .hue), 0)
        XCTAssertEqual(viewModel.mixerValue(for: .red, control: .saturation), 35)

        viewModel.resetGrading(.midtones, .saturation)
        XCTAssertEqual(viewModel.gradingValue(for: .midtones, control: .saturation), 0)
        XCTAssertEqual(viewModel.gradingValue(for: .midtones, control: .hue), 120)

        viewModel.resetEffects(.texture)
        XCTAssertEqual(viewModel.effectsValue(for: .texture), 0)
        XCTAssertEqual(viewModel.effectsValue(for: .clarity), -18)

        viewModel.resetVignette(.amount)
        XCTAssertEqual(viewModel.vignetteValue(for: .amount), 0)
        XCTAssertEqual(viewModel.vignetteValue(for: .midpoint), 42)

        viewModel.resetGrain(.roughness)
        XCTAssertEqual(viewModel.grainValue(for: .roughness), GrainControl.roughness.neutral)
        XCTAssertEqual(viewModel.grainValue(for: .size), 20)
    }

    func testResetEndsAnActiveSliderGroupBeforeRecordingItsOwnUndoEntry() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }

        viewModel.beginPreviewInteraction()
        viewModel.adjustmentBinding(for: .exposure).wrappedValue = 1.5
        viewModel.resetAdjustment(.exposure)

        XCTAssertEqual(viewModel.adjustmentValue(for: .exposure), AdjustmentControl.exposure.neutral)
        viewModel.undo()
        XCTAssertEqual(viewModel.adjustmentValue(for: .exposure), 1.5)
        viewModel.undo()
        XCTAssertEqual(viewModel.adjustmentValue(for: .exposure), 0.5)
    }

    func testInspectorSectionResetDoesNotCrossStageBoundariesAndIsUndoable() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument {
            $0.light.exposure = 1
            $0.effects.texture = 25
        }

        viewModel.inspectorTab = .effects
        viewModel.resetInspectorSection()

        XCTAssertTrue(viewModel.document.effects.isIdentity)
        XCTAssertEqual(viewModel.document.light.exposure, 1)

        viewModel.undo()
        XCTAssertEqual(viewModel.document.effects.texture, 25)
        XCTAssertEqual(viewModel.document.light.exposure, 1)
    }

    func testResetPhotoClearsEveryStageAsOneUndoableOperation() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument {
            $0.rawDevelop.exposure = 1
            $0.light.exposure = 1
            $0.adjustments = [.exposure(ev: 0.5)]
            $0.effects.texture = 25
            $0.lut.lutID = LUTID(raw: "look.cube")
        }

        viewModel.resetPhoto()

        XCTAssertEqual(viewModel.document, EditDocument())
        XCTAssertEqual(viewModel.undoDepth, 2)

        viewModel.undo()
        XCTAssertEqual(viewModel.document.rawDevelop.exposure, 1)
        XCTAssertEqual(viewModel.document.light.exposure, 1)
        XCTAssertEqual(viewModel.document.effects.texture, 25)
        XCTAssertEqual(viewModel.document.lut.lutID, LUTID(raw: "look.cube"))
    }
}
