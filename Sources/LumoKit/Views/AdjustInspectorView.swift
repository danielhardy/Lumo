import SwiftUI

/// Tone and colour adjustments — the nodes that run *after* the develop stage and *before* the LUT.
///
/// **One state, where `DevelopInspectorView` has three.** That asymmetry is the honest one: Develop's
/// three states exist because *the file* answers a question — is there a decode stage, and has the
/// capability probe landed yet — and here there is no question to ask. Adjustments are applied to an
/// already-developed image. Temperature/tint are the standard-image fallback; RAWs use the decoder
/// controls in Develop instead, so those two rows are intentionally absent from this panel for RAW.
///
/// Nine rows over five `AdjustmentNode` cases, one row per parameter for standard images. RAW images
/// omit the post-render white-balance pair because Develop owns that pair in `CIRAWFilter`; this
/// keeps one user-facing white-balance control from silently becoming two stacked color casts.
struct AdjustInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(Array(viewModel.visibleAdjustmentControls.enumerated()), id: \.element) { offset, control in
                    controlRow(
                        control,
                        sortPriority: Double(viewModel.visibleAdjustmentControls.count - offset)
                    )
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack {
            Text("Adjustments").font(.headline)
            Spacer()
            Button("Reset") { viewModel.resetAllAdjustments() }
                .buttonStyle(.link)
                .disabled(!viewModel.hasAdjustments)
        }
    }

    @ViewBuilder
    private func controlRow(_ control: AdjustmentControl, sortPriority: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ResettableAdjustmentLabel(
                    title: control.title,
                    reset: { viewModel.resetAdjustment(control) }
                )
                Spacer()
                Text(readout(for: control))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Slider(
                value: viewModel.adjustmentBinding(for: control),
                in: control.range,
                onEditingChanged: { editing in
                    if editing {
                        viewModel.beginPreviewInteraction()
                    } else {
                        viewModel.endPreviewInteraction()
                    }
                }
            )
            .accessibilityLabel(control.title)
            .accessibilityValue(readout(for: control))
            .accessibilitySortPriority(sortPriority)
            .accessibilityAction(named: Text("Reset to neutral")) {
                viewModel.resetAdjustment(control)
            }
        }
    }

    /// Kelvin reads as a whole number; everything else to two places. 5842.20 K is noise on a
    /// slider whose useful travel is thousands of degrees wide.
    private func readout(for control: AdjustmentControl) -> String {
        let value = viewModel.adjustmentValue(for: control)
        switch control {
        case .temperature:
            return String(format: "%.0f K", value)
        case .exposure, .brightness, .contrast, .saturation, .highlights, .shadows, .tint, .vibrance:
            return String(format: "%.2f", value)
        }
    }
}
