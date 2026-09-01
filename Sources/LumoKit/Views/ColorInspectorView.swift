import SwiftUI

/// The photographer-facing colour surface.
///
/// Each major tool is a native disclosure section so the inspector remains useful at its narrow
/// dock width. Sliders and numeric fields share the same view-model binding; a slider drag uses the
/// preview coordinator's interactive quality while a committed field value follows the normal
/// debounced settled path.
struct ColorInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var whiteBalanceExpanded = true
    @State private var colorExpanded = true
    @State private var mixerExpanded = false
    @State private var gradingExpanded = false
    @State private var expandedMixerChannels = Set(ColorMixerChannelName.allCases)
    @State private var expandedGradingZones = Set(ColorGradingZone.allCases)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                whiteBalanceSection
                colorSection
                mixerSection
                gradingSection
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color adjustments")
    }

    private var header: some View {
        Text("Color")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private var whiteBalanceSection: some View {
        DisclosureGroup("White Balance", isExpanded: $whiteBalanceExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(viewModel.sourceIsRAW ? "RAW decoder" : "Standard image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("As Shot") { viewModel.resetWhiteBalance() }
                        .buttonStyle(.link)
                        .disabled(!viewModel.hasWhiteBalanceAdjustments)
                        .accessibilityLabel("Reset white balance to As Shot")
                }

                if viewModel.sourceIsRAW && viewModel.rawCapabilities == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the decoder's white balance…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    valueRow(
                        title: "Temperature",
                        value: viewModel.whiteBalanceBinding(for: .temperature),
                        range: viewModel.sourceIsRAW
                            ? DevelopControl.whiteBalance.range
                            : AdjustmentControl.temperature.range,
                        readout: temperatureReadout,
                        reset: { viewModel.resetWhiteBalance(.temperature) },
                        disabled: viewModel.sourceIsRAW && viewModel.rawCapabilities == nil
                    )
                    valueRow(
                        title: "Tint",
                        value: viewModel.whiteBalanceBinding(for: .tint),
                        range: viewModel.sourceIsRAW
                            ? DevelopControl.tintRange
                            : AdjustmentControl.tint.range,
                        readout: tintReadout,
                        reset: { viewModel.resetWhiteBalance(.tint) },
                        disabled: viewModel.sourceIsRAW && viewModel.rawCapabilities == nil
                    )
                }
            }
            .padding(.top, 10)
        }
        .accessibilityLabel("White Balance")
    }

    private var colorSection: some View {
        DisclosureGroup("Color", isExpanded: $colorExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                sectionResetButton(
                    title: "Reset Color",
                    disabled: !viewModel.hasColorAdjustments,
                    action: viewModel.resetAllColor
                )
                ForEach(ColorGlobalControl.allCases, id: \.self) { control in
                    valueRow(
                        title: control.title,
                        value: viewModel.colorBinding(for: control),
                        range: control.range,
                        readout: signedWholeReadout,
                        reset: { viewModel.resetColor(control) }
                    )
                }
            }
            .padding(.top, 10)
        }
    }

    private var mixerSection: some View {
        DisclosureGroup("Color Mixer / HSL", isExpanded: $mixerExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                sectionResetButton(
                    title: "Reset Mixer",
                    disabled: !viewModel.hasMixerAdjustments,
                    action: viewModel.resetAllMixer
                )
                ForEach(ColorMixerChannelName.allCases, id: \.self) { channel in
                    DisclosureGroup(
                        channel.title,
                        isExpanded: mixerExpansion(for: channel)
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(ColorMixerControl.allCases, id: \.self) { control in
                                valueRow(
                                    title: "\(channel.title) \(control.title)",
                                    value: viewModel.mixerBinding(for: channel, control: control),
                                    range: control.range,
                                    readout: signedWholeReadout,
                                    reset: {
                                        viewModel.resetMixer(channel, control)
                                    }
                                )
                            }
                            sectionResetButton(
                                title: "Reset \(channel.title)",
                                disabled: viewModel.mixerChannelValue(channel).isIdentity,
                                action: { viewModel.resetMixer(channel) }
                            )
                        }
                        .padding(.top, 8)
                    }
                    .accessibilityLabel("\(channel.title) mixer channel")
                }
            }
            .padding(.top, 10)
        }
    }

    private var gradingSection: some View {
        DisclosureGroup("Color Grading", isExpanded: $gradingExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                sectionResetButton(
                    title: "Reset Grading",
                    disabled: !viewModel.hasGradingAdjustments,
                    action: viewModel.resetAllGrading
                )
                ForEach(ColorGradingZone.allCases, id: \.self) { zone in
                    DisclosureGroup(
                        zone.title,
                        isExpanded: gradingExpansion(for: zone)
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(ColorGradingControl.allCases, id: \.self) { control in
                                valueRow(
                                    title: "\(zone.title) \(control.title)",
                                    value: viewModel.gradingBinding(for: zone, control: control),
                                    range: control.range,
                                    readout: control == .hue ? hueReadout : unsignedWholeReadout,
                                    reset: { viewModel.resetGrading(zone, control) }
                                )
                            }
                            sectionResetButton(
                                title: "Reset \(zone.title)",
                                disabled: viewModel.gradingWheelValue(zone).isIdentity,
                                action: { viewModel.resetGrading(zone) }
                            )
                        }
                        .padding(.top, 8)
                    }
                    .accessibilityLabel("\(zone.title) color grading wheel")
                }
                ForEach(ColorGradingGlobalControl.allCases, id: \.self) { control in
                    valueRow(
                        title: control.title,
                        value: viewModel.gradingGlobalBinding(for: control),
                        range: control.range,
                        readout: control == .blending ? unsignedWholeReadout : signedWholeReadout,
                        reset: { viewModel.resetGrading(control) }
                    )
                }
            }
            .padding(.top, 10)
        }
    }

    private func sectionResetButton(
        title: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Spacer()
            Button(title, action: action)
                .buttonStyle(.link)
                .disabled(disabled)
        }
    }

    private func valueRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        readout: @escaping (Double) -> String,
        reset: @escaping () -> Void,
        disabled: Bool = false
    ) -> some View {
        ColorValueRow(
            title: title,
            value: value,
            range: range,
            readout: readout,
            reset: reset,
            beginInteraction: viewModel.beginPreviewInteraction,
            endInteraction: viewModel.endPreviewInteraction
        )
        .disabled(disabled)
    }

    private var temperatureReadout: (Double) -> String {
        { value in String(format: "%.0f K", value) }
    }

    private var tintReadout: (Double) -> String {
        { value in String(format: "%+.0f", value) }
    }

    private var signedWholeReadout: (Double) -> String {
        { value in String(format: "%+.0f", value) }
    }

    private var unsignedWholeReadout: (Double) -> String {
        { value in String(format: "%.0f", value) }
    }

    private var hueReadout: (Double) -> String {
        { value in String(format: "%.0f°", value) }
    }

    private func mixerExpansion(for channel: ColorMixerChannelName) -> Binding<Bool> {
        Binding(
            get: { expandedMixerChannels.contains(channel) },
            set: { expanded in
                if expanded { expandedMixerChannels.insert(channel) }
                else { expandedMixerChannels.remove(channel) }
            }
        )
    }

    private func gradingExpansion(for zone: ColorGradingZone) -> Binding<Bool> {
        Binding(
            get: { expandedGradingZones.contains(zone) },
            set: { expanded in
                if expanded { expandedGradingZones.insert(zone) }
                else { expandedGradingZones.remove(zone) }
            }
        )
    }
}

/// Shared slider + numeric-entry row. The full contextual title is applied to both controls so
/// VoiceOver can distinguish repeated Hue/Saturation/Luminance labels across channels and wheels.
private struct ColorValueRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let readout: (Double) -> String
    let reset: () -> Void
    let beginInteraction: () -> Void
    let endInteraction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField(title, value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 68)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(title)
                    .accessibilityValue(readout(value))
                Button(action: reset) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Reset \(title)")
                .accessibilityLabel("Reset \(title)")
            }

            Slider(
                value: $value,
                in: range,
                onEditingChanged: { editing in
                    if editing { beginInteraction() }
                    else { endInteraction() }
                }
            )
            .accessibilityLabel(title)
            .accessibilityValue(readout(value))
        }
    }
}
