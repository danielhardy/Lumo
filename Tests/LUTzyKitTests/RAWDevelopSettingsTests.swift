import XCTest
import CoreImage
@testable import LUTzyKit

/// `RAWDevelopSettings` is the one Step 2 type with a foot in the framework: its whole job is to push
/// values onto a `CIRAWFilter` before `outputImage` is read.
///
/// Two things are worth proving. First that `.neutral` is genuinely nothing — the migration's promise
/// is that an untouched document renders byte-identically to today's `ImageDecoder.developRAWNeutral`,
/// which sets no properties at all. Second that the property set is the real one: an earlier draft of
/// the spec listed names (`isDustRemovalSupported`, `enableEDR`) that do not exist.
final class RAWDevelopSettingsTests: XCTestCase {

    // MARK: - Neutral

    /// `.neutral` has to be equal to a default-constructed value and to hold nothing, because `nil`
    /// is what stands for "leave the decoder alone". Several `CIRAWFilter` defaults vary per image,
    /// so there is no fixed number that could mean "untouched" — a numeric sentinel here would
    /// silently override a per-camera baseline.
    func testNeutralIsEmptyAndEqualsADefaultValue() {
        XCTAssertEqual(RAWDevelopSettings.neutral, RAWDevelopSettings())
        XCTAssertTrue(RAWDevelopSettings.neutral.isNeutral)
        XCTAssertTrue(RAWDevelopSettings().isNeutral)
        XCTAssertEqual(EditDocument().rawDevelop, .neutral)

        let neutral = RAWDevelopSettings.neutral
        XCTAssertNil(neutral.exposure)
        XCTAssertNil(neutral.baselineExposure)
        XCTAssertNil(neutral.shadowBias)
        XCTAssertNil(neutral.boostAmount)
        XCTAssertNil(neutral.boostShadowAmount)
        XCTAssertNil(neutral.neutralTemperature)
        XCTAssertNil(neutral.neutralTint)
        XCTAssertNil(neutral.sharpnessAmount)
        XCTAssertNil(neutral.contrastAmount)
        XCTAssertNil(neutral.detailAmount)
        XCTAssertNil(neutral.moireReductionAmount)
        XCTAssertNil(neutral.localToneMapAmount)
        XCTAssertNil(neutral.luminanceNoiseReductionAmount)
        XCTAssertNil(neutral.colorNoiseReductionAmount)
        XCTAssertNil(neutral.lensCorrectionEnabled)
        XCTAssertNil(neutral.gamutMappingEnabled)
        XCTAssertNil(neutral.extendedDynamicRangeAmount)
        XCTAssertNil(neutral.highlightRecoveryEnabled)
    }

    /// Every field has to break neutrality on its own — a knob that isn't compared is a knob whose
    /// change won't invalidate a cached render.
    func testAnySingleSettingBreaksNeutrality() throws {
        var mutations: [(String, RAWDevelopSettings)] = []
        func vary(_ name: String, _ mutate: (inout RAWDevelopSettings) -> Void) {
            var settings = RAWDevelopSettings.neutral
            mutate(&settings)
            mutations.append((name, settings))
        }

        vary("exposure") { $0.exposure = 1 }
        vary("baselineExposure") { $0.baselineExposure = 1 }
        vary("shadowBias") { $0.shadowBias = 1 }
        vary("boostAmount") { $0.boostAmount = 0 }
        vary("boostShadowAmount") { $0.boostShadowAmount = 0 }
        vary("neutralTemperature") { $0.neutralTemperature = 5000 }
        vary("neutralTint") { $0.neutralTint = 10 }
        vary("sharpnessAmount") { $0.sharpnessAmount = 0.5 }
        vary("contrastAmount") { $0.contrastAmount = 0.5 }
        vary("detailAmount") { $0.detailAmount = 1 }
        vary("moireReductionAmount") { $0.moireReductionAmount = 0.5 }
        vary("localToneMapAmount") { $0.localToneMapAmount = 0.5 }
        vary("luminanceNoiseReductionAmount") { $0.luminanceNoiseReductionAmount = 0.5 }
        vary("colorNoiseReductionAmount") { $0.colorNoiseReductionAmount = 0.5 }
        vary("lensCorrectionEnabled") { $0.lensCorrectionEnabled = true }
        vary("gamutMappingEnabled") { $0.gamutMappingEnabled = false }
        vary("extendedDynamicRangeAmount") { $0.extendedDynamicRangeAmount = 1 }
        vary("highlightRecoveryEnabled") { $0.highlightRecoveryEnabled = false }

        XCTAssertEqual(mutations.count, 18, "a new property needs a case here")
        for (name, settings) in mutations {
            XCTAssertFalse(settings.isNeutral, "\(name) should count as an edit")
            XCTAssertNotEqual(settings, .neutral, "\(name) should be part of equality")
        }
        // And no two of them collide, which would mean one field is being compared as another.
        let encoded = try mutations.map { try JSONEncoder().encode($0.1) }
        XCTAssertEqual(Set(encoded).count, 18)
    }

    func testSettingsRoundTripAndOmitNilFields() throws {
        let settings = RAWDevelopSettings(exposure: -1.25, neutralTint: 33, gamutMappingEnabled: false)
        let data = try JSONEncoder().encode(settings)

        XCTAssertEqual(try JSONDecoder().decode(RAWDevelopSettings.self, from: data), settings)

        // `nil` means "decoder default", so it should not be written at all — a document full of
        // explicit nulls is both larger and easy to misread as "set to zero".
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["exposure", "neutralTint", "gamutMappingEnabled"])

        XCTAssertEqual(try JSONDecoder().decode(RAWDevelopSettings.self, from: Data("{}".utf8)), .neutral)
    }

    // MARK: - Application to a real CIRAWFilter

    /// The knob names are checked by the compiler; what this checks is that they *do something* —
    /// that each one round-trips through a real `CIRAWFilter` built from a real RAW.
    ///
    /// Skipped wherever there is no RAW to hand, which includes CI. See `Fixtures.localRAWURL`.
    func testApplyPushesEverySupportedKnobOntoARealFilter() throws {
        guard let url = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }

        let filter = try XCTUnwrap(CIRAWFilter(imageURL: url), "CIRAWFilter could not decode \(url.lastPathComponent)")

        let settings = RAWDevelopSettings(
            exposure: 0.5,
            baselineExposure: 0.25,
            shadowBias: -0.1,
            boostAmount: 0.75,
            boostShadowAmount: 1.5,
            neutralTemperature: 5200,
            neutralTint: 12,
            sharpnessAmount: 0.4,
            contrastAmount: 0.6,
            detailAmount: 1.5,
            moireReductionAmount: 0.2,
            localToneMapAmount: 0.3,
            luminanceNoiseReductionAmount: 0.7,
            colorNoiseReductionAmount: 0.8,
            // Both booleans are written as `false` on purpose. `CIRAWFilter` defaults them to
            // *true* for this file, so a test that set `true` and asserted `true` would pass just as
            // happily against an `apply(to:)` that skipped them entirely — which is exactly what a
            // mutation check caught it doing.
            lensCorrectionEnabled: false,
            gamutMappingEnabled: false,
            extendedDynamicRangeAmount: 1.0,
            highlightRecoveryEnabled: false
        )
        settings.apply(to: filter)

        XCTAssertEqual(filter.exposure, 0.5, accuracy: 0.0001)
        XCTAssertEqual(filter.baselineExposure, 0.25, accuracy: 0.0001)
        XCTAssertEqual(filter.shadowBias, -0.1, accuracy: 0.0001)
        XCTAssertEqual(filter.boostAmount, 0.75, accuracy: 0.0001)
        XCTAssertEqual(filter.boostShadowAmount, 1.5, accuracy: 0.0001)
        XCTAssertEqual(filter.neutralTemperature, 5200, accuracy: 1)
        XCTAssertEqual(filter.neutralTint, 12, accuracy: 0.5)
        XCTAssertFalse(filter.isGamutMappingEnabled)
        XCTAssertEqual(filter.extendedDynamicRangeAmount, 1.0, accuracy: 0.0001)

        // The gated knobs: assert only where this file's decoder offers the adjustment. Whether a
        // given camera supports moire reduction is not this test's business; whether the value lands
        // when it does is.
        if filter.isSharpnessSupported { XCTAssertEqual(filter.sharpnessAmount, 0.4, accuracy: 0.0001) }
        if filter.isContrastSupported { XCTAssertEqual(filter.contrastAmount, 0.6, accuracy: 0.0001) }
        if filter.isDetailSupported { XCTAssertEqual(filter.detailAmount, 1.5, accuracy: 0.0001) }
        if filter.isMoireReductionSupported { XCTAssertEqual(filter.moireReductionAmount, 0.2, accuracy: 0.0001) }
        if filter.isLocalToneMapSupported { XCTAssertEqual(filter.localToneMapAmount, 0.3, accuracy: 0.0001) }
        if filter.isLuminanceNoiseReductionSupported {
            XCTAssertEqual(filter.luminanceNoiseReductionAmount, 0.7, accuracy: 0.0001)
        }
        if filter.isColorNoiseReductionSupported {
            XCTAssertEqual(filter.colorNoiseReductionAmount, 0.8, accuracy: 0.0001)
        }
        if filter.isLensCorrectionSupported { XCTAssertFalse(filter.isLensCorrectionEnabled) }
        if #available(macOS 26, *), filter.isHighlightRecoverySupported {
            XCTAssertFalse(filter.isHighlightRecoveryEnabled)
        }

        XCTAssertNotNil(filter.outputImage, "a configured filter must still produce an image")
    }

    /// The migration's actual promise: applying `.neutral` leaves the filter exactly as the decoder
    /// built it, so an untouched document renders identically to today's `developRAWNeutral`.
    func testApplyingNeutralChangesNothingOnARealFilter() throws {
        guard let url = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }

        // Two filters from the same file start identical; only one of them is touched.
        let reference = try XCTUnwrap(CIRAWFilter(imageURL: url))
        let subject = try XCTUnwrap(CIRAWFilter(imageURL: url))
        RAWDevelopSettings.neutral.apply(to: subject)

        XCTAssertEqual(subject.exposure, reference.exposure)
        XCTAssertEqual(subject.baselineExposure, reference.baselineExposure)
        XCTAssertEqual(subject.shadowBias, reference.shadowBias)
        XCTAssertEqual(subject.boostAmount, reference.boostAmount)
        XCTAssertEqual(subject.boostShadowAmount, reference.boostShadowAmount)
        XCTAssertEqual(subject.neutralTemperature, reference.neutralTemperature)
        XCTAssertEqual(subject.neutralTint, reference.neutralTint)
        XCTAssertEqual(subject.sharpnessAmount, reference.sharpnessAmount)
        XCTAssertEqual(subject.contrastAmount, reference.contrastAmount)
        XCTAssertEqual(subject.detailAmount, reference.detailAmount)
        XCTAssertEqual(subject.moireReductionAmount, reference.moireReductionAmount)
        XCTAssertEqual(subject.localToneMapAmount, reference.localToneMapAmount)
        XCTAssertEqual(subject.luminanceNoiseReductionAmount, reference.luminanceNoiseReductionAmount)
        XCTAssertEqual(subject.colorNoiseReductionAmount, reference.colorNoiseReductionAmount)
        XCTAssertEqual(subject.isLensCorrectionEnabled, reference.isLensCorrectionEnabled)
        XCTAssertEqual(subject.isGamutMappingEnabled, reference.isGamutMappingEnabled)
        XCTAssertEqual(subject.extendedDynamicRangeAmount, reference.extendedDynamicRangeAmount)
        if #available(macOS 26, *) {
            XCTAssertEqual(subject.isHighlightRecoveryEnabled, reference.isHighlightRecoveryEnabled)
        }
    }

    // The `is*Supported` gates in `apply(to:)` are deliberately not covered by a test. Exercising one
    // needs a RAW whose decoder *lacks* that adjustment, and the file this suite can reach supports
    // all of them — a test that skips both here and in CI is noise, not coverage.
}
