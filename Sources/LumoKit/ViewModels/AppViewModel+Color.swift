import SwiftUI

/// The photographer-facing controls in the global Color stage.
enum ColorGlobalControl: String, CaseIterable, Hashable, Sendable {
    case vibrance
    case saturation

    var title: String {
        switch self {
        case .vibrance: return "Vibrance"
        case .saturation: return "Saturation"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .vibrance: return ColorAdjustments.vibranceRange
        case .saturation: return ColorAdjustments.saturationRange
        }
    }
}

enum ColorMixerControl: String, CaseIterable, Hashable, Sendable {
    case hue
    case saturation
    case luminance

    var title: String {
        switch self {
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        case .luminance: return "Luminance"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .hue: return ColorMixerChannel.hueRange
        case .saturation: return ColorMixerChannel.saturationRange
        case .luminance: return ColorMixerChannel.luminanceRange
        }
    }
}

enum ColorMixerChannelName: String, CaseIterable, Hashable, Sendable {
    case red, orange, yellow, green, aqua, blue, purple, magenta

    var title: String { rawValue.capitalized }
}

enum ColorGradingZone: String, CaseIterable, Hashable, Sendable {
    case shadows, midtones, highlights

    var title: String { rawValue.capitalized }
}

enum ColorGradingControl: String, CaseIterable, Hashable, Sendable {
    case hue
    case saturation

    var title: String {
        switch self {
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .hue: return ColorGradingWheel.hueRange
        case .saturation: return ColorGradingWheel.saturationRange
        }
    }
}

enum ColorGradingGlobalControl: String, CaseIterable, Hashable, Sendable {
    case blending
    case balance

    var title: String { rawValue.capitalized }

    var range: ClosedRange<Double> {
        switch self {
        case .blending: return ColorGradingAdjustments.blendingRange
        case .balance: return ColorGradingAdjustments.balanceRange
        }
    }
}

extension AppViewModel {
    // MARK: - White balance

    /// Whether the Color inspector's white-balance rows have a non-neutral value.
    ///
    /// A RAW stores an override in `rawDevelop`; standard images store the post-render fallback in
    /// the legacy temperature/tint node. Include both forms so an older per-photo session can be
    /// reset even when it was created before RAW-aware white balance was introduced.
    var hasWhiteBalanceAdjustments: Bool {
        document.rawDevelop.neutralTemperature != nil || document.rawDevelop.neutralTint != nil ||
            AdjustmentControl.temperature.value(in: document.adjustments) != AdjustmentControl.temperature.neutral ||
            AdjustmentControl.tint.value(in: document.adjustments) != AdjustmentControl.tint.neutral
    }

    func whiteBalanceBinding(for control: AdjustmentControl) -> Binding<Double> {
        precondition(control == .temperature || control == .tint)
        if sourceIsRAW {
            return control == .temperature
                ? developBinding(for: .whiteBalance)
                : developTintBinding()
        }
        return adjustmentBinding(for: control)
    }

    func whiteBalanceValue(for control: AdjustmentControl) -> Double {
        precondition(control == .temperature || control == .tint)
        if sourceIsRAW {
            return control == .temperature
                ? developValue(for: .whiteBalance)
                : (document.rawDevelop.neutralTint ?? rawCapabilities?.asShotTint ?? 0)
        }
        return adjustmentValue(for: control)
    }

    /// Reset one white-balance row. RAW decoders expose the pair as one neutral/default operation;
    /// standard images can reset the temperature and tint nodes independently.
    func resetWhiteBalance(_ control: AdjustmentControl) {
        precondition(control == .temperature || control == .tint)
        if sourceIsRAW {
            resetWhiteBalance()
        } else {
            endUndoGrouping()
            resetAdjustment(control)
        }
    }

    // MARK: - Global Color

    func colorValue(for control: ColorGlobalControl) -> Double {
        switch control {
        case .vibrance: return document.color.vibrance
        case .saturation: return document.color.saturation
        }
    }

    func colorBinding(for control: ColorGlobalControl) -> Binding<Double> {
        Binding(
            get: { self.colorValue(for: control) },
            set: { value in
                self.updateDocument(debounced: true) { document in
                    switch control {
                    case .vibrance: document.color.vibrance = value
                    case .saturation: document.color.saturation = value
                    }
                }
            }
        )
    }

    func resetColor(_ control: ColorGlobalControl) {
        endUndoGrouping()
        updateDocument { document in
            switch control {
            case .vibrance: document.color.vibrance = 0
            case .saturation: document.color.saturation = 0
            }
        }
    }

    func resetAllColor() {
        endUndoGrouping()
        updateDocument { document in
            document.color.vibrance = 0
            document.color.saturation = 0
        }
    }

    var hasColorAdjustments: Bool {
        document.color.vibrance != 0 || document.color.saturation != 0
    }

    // MARK: - Color Mixer

    func mixerChannelValue(_ channel: ColorMixerChannelName) -> ColorMixerChannel {
        switch channel {
        case .red: return document.color.mixer.red
        case .orange: return document.color.mixer.orange
        case .yellow: return document.color.mixer.yellow
        case .green: return document.color.mixer.green
        case .aqua: return document.color.mixer.aqua
        case .blue: return document.color.mixer.blue
        case .purple: return document.color.mixer.purple
        case .magenta: return document.color.mixer.magenta
        }
    }

    func mixerValue(for channel: ColorMixerChannelName, control: ColorMixerControl) -> Double {
        let value = mixerChannelValue(channel)
        switch control {
        case .hue: return value.hue
        case .saturation: return value.saturation
        case .luminance: return value.luminance
        }
    }

    func mixerBinding(
        for channel: ColorMixerChannelName, control: ColorMixerControl
    ) -> Binding<Double> {
        Binding(
            get: { self.mixerValue(for: channel, control: control) },
            set: { value in
                self.updateDocument(debounced: true) { document in
                    var channelValue = self.mixerChannelValue(channel)
                    switch control {
                    case .hue: channelValue.hue = value
                    case .saturation: channelValue.saturation = value
                    case .luminance: channelValue.luminance = value
                    }
                    Self.setMixerChannel(channel, to: channelValue, in: &document.color.mixer)
                }
            }
        )
    }

    func resetMixer(_ channel: ColorMixerChannelName) {
        endUndoGrouping()
        updateDocument { document in
            Self.setMixerChannel(channel, to: .neutral, in: &document.color.mixer)
        }
    }

    func resetMixer(_ channel: ColorMixerChannelName, _ control: ColorMixerControl) {
        endUndoGrouping()
        updateDocument { document in
            var value = self.mixerChannelValue(channel)
            switch control {
            case .hue: value.hue = 0
            case .saturation: value.saturation = 0
            case .luminance: value.luminance = 0
            }
            Self.setMixerChannel(channel, to: value, in: &document.color.mixer)
        }
    }

    func resetAllMixer() {
        endUndoGrouping()
        updateDocument { $0.color.mixer = .neutral }
    }

    var hasMixerAdjustments: Bool { !document.color.mixer.isIdentity }

    // MARK: - Color Grading

    func gradingWheelValue(_ zone: ColorGradingZone) -> ColorGradingWheel {
        switch zone {
        case .shadows: return document.color.grading.shadows
        case .midtones: return document.color.grading.midtones
        case .highlights: return document.color.grading.highlights
        }
    }

    func gradingValue(for zone: ColorGradingZone, control: ColorGradingControl) -> Double {
        let value = gradingWheelValue(zone)
        switch control {
        case .hue: return value.hue
        case .saturation: return value.saturation
        }
    }

    func gradingBinding(
        for zone: ColorGradingZone, control: ColorGradingControl
    ) -> Binding<Double> {
        Binding(
            get: { self.gradingValue(for: zone, control: control) },
            set: { value in
                self.updateDocument(debounced: true) { document in
                    var wheel = self.gradingWheelValue(zone)
                    switch control {
                    case .hue: wheel.hue = value
                    case .saturation: wheel.saturation = value
                    }
                    Self.setGradingWheel(zone, to: wheel, in: &document.color.grading)
                }
            }
        )
    }

    /// The visual wheel changes hue and saturation together, so it needs one binding rather than
    /// composing the two numeric bindings. It still takes the normal debounced render path and
    /// therefore remains pixel-identical to precise numeric entry.
    func gradingWheelBinding(for zone: ColorGradingZone) -> Binding<ColorGradingWheel> {
        Binding(
            get: { self.gradingWheelValue(zone) },
            set: { wheel in
                self.updateDocument(debounced: true) { document in
                    Self.setGradingWheel(zone, to: wheel, in: &document.color.grading)
                }
            }
        )
    }

    func gradingGlobalValue(for control: ColorGradingGlobalControl) -> Double {
        switch control {
        case .blending: return document.color.grading.blending
        case .balance: return document.color.grading.balance
        }
    }

    func gradingGlobalBinding(for control: ColorGradingGlobalControl) -> Binding<Double> {
        Binding(
            get: { self.gradingGlobalValue(for: control) },
            set: { value in
                self.updateDocument(debounced: true) { document in
                    switch control {
                    case .blending: document.color.grading.blending = value
                    case .balance: document.color.grading.balance = value
                    }
                }
            }
        )
    }

    func resetGrading(_ zone: ColorGradingZone) {
        endUndoGrouping()
        updateDocument { document in
            Self.setGradingWheel(zone, to: .neutral, in: &document.color.grading)
        }
    }

    func resetGrading(_ zone: ColorGradingZone, _ control: ColorGradingControl) {
        endUndoGrouping()
        updateDocument { document in
            var value = self.gradingWheelValue(zone)
            switch control {
            case .hue: value.hue = 0
            case .saturation: value.saturation = 0
            }
            Self.setGradingWheel(zone, to: value, in: &document.color.grading)
        }
    }

    func resetGrading(_ control: ColorGradingGlobalControl) {
        endUndoGrouping()
        updateDocument { document in
            switch control {
            case .blending: document.color.grading.blending = ColorGradingAdjustments.neutral.blending
            case .balance: document.color.grading.balance = ColorGradingAdjustments.neutral.balance
            }
        }
    }

    func resetAllGrading() {
        endUndoGrouping()
        updateDocument { $0.color.grading = .neutral }
    }

    var hasGradingAdjustments: Bool { !document.color.grading.isIdentity }

    // MARK: - Nested value helpers

    private static func setMixerChannel(
        _ channel: ColorMixerChannelName,
        to value: ColorMixerChannel,
        in mixer: inout ColorMixerAdjustments
    ) {
        switch channel {
        case .red: mixer.red = value
        case .orange: mixer.orange = value
        case .yellow: mixer.yellow = value
        case .green: mixer.green = value
        case .aqua: mixer.aqua = value
        case .blue: mixer.blue = value
        case .purple: mixer.purple = value
        case .magenta: mixer.magenta = value
        }
    }

    private static func setGradingWheel(
        _ zone: ColorGradingZone,
        to value: ColorGradingWheel,
        in grading: inout ColorGradingAdjustments
    ) {
        switch zone {
        case .shadows: grading.shadows = value
        case .midtones: grading.midtones = value
        case .highlights: grading.highlights = value
        }
    }
}
