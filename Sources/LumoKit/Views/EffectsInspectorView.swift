import SwiftUI

/// The photographer-facing global Effects inspector.
///
/// All rows use the same value-state bindings as the render pipeline. Slider ticks take the
/// interactive quality path and a gesture becomes one undo entry; numeric edits and resets retain
/// the existing settled/debounced behavior from `AppViewModel`.
struct EffectsInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var detailExpanded = true
    @State private var vignetteExpanded = false
    @State private var grainExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                detailSection
                vignetteSection
                grainSection
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Effects adjustments")
    }

    private var header: some View {
        HStack {
            Text("Effects")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Reset Effects") { viewModel.resetAllEffects() }
                .buttonStyle(.link)
                .disabled(!viewModel.hasEffects)
                .accessibilityHint("Reset Texture, Clarity, Dehaze, Vignette, and Grain")
        }
    }

    private var detailSection: some View {
        DisclosureGroup("Texture / Clarity / Dehaze", isExpanded: $detailExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                sectionResetButton(
                    title: "Reset Texture / Clarity / Dehaze",
                    disabled: !viewModel.hasDetailEffects,
                    action: viewModel.resetAllDetailEffects
                )
                ForEach(EffectsControl.allCases, id: \.self) { control in
                    valueRow(
                        title: control.title,
                        value: viewModel.effectsBinding(for: control),
                        range: control.range,
                        readout: signedWholeReadout,
                        reset: { viewModel.resetEffects(control) }
                    )
                }
            }
            .padding(.top, 10)
        }
    }

    private var vignetteSection: some View {
        DisclosureGroup("Vignette", isExpanded: $vignetteExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                sectionResetButton(
                    title: "Reset Vignette",
                    disabled: !viewModel.hasVignetteAdjustments,
                    action: viewModel.resetAllVignette
                )
                ForEach(VignetteControl.allCases, id: \.self) { control in
                    valueRow(
                        title: control.title,
                        value: viewModel.vignetteBinding(for: control),
                        range: control.range,
                        readout: control == .amount || control == .roundness
                            ? signedWholeReadout : unsignedWholeReadout,
                        reset: { viewModel.resetVignette(control) }
                    )
                }
            }
            .padding(.top, 10)
        }
    }

    private var grainSection: some View {
        DisclosureGroup("Grain", isExpanded: $grainExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                sectionResetButton(
                    title: "Reset Grain",
                    disabled: !viewModel.hasGrainAdjustments,
                    action: viewModel.resetAllGrain
                )
                ForEach(GrainControl.allCases, id: \.self) { control in
                    valueRow(
                        title: control.title,
                        value: viewModel.grainBinding(for: control),
                        range: control.range,
                        readout: unsignedWholeReadout,
                        reset: { viewModel.resetGrain(control) }
                    )
                }
            }
            .padding(.top, 10)
        }
    }

    private func valueRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        readout: @escaping (Double) -> String,
        reset: @escaping () -> Void
    ) -> some View {
        EffectsValueRow(
            title: title,
            value: value,
            range: range,
            readout: readout,
            reset: reset,
            beginInteraction: viewModel.beginPreviewInteraction,
            endInteraction: viewModel.endPreviewInteraction
        )
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

    private var signedWholeReadout: (Double) -> String {
        { value in String(format: "%+.0f", value) }
    }

    private var unsignedWholeReadout: (Double) -> String {
        { value in String(format: "%.0f", value) }
    }
}

private struct EffectsValueRow: View {
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
