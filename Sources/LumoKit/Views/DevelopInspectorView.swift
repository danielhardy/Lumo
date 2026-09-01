import SwiftUI

/// RAW develop controls, gated per image on what the file's decoder actually supports.
///
/// The control list is not written out here — it comes from `RAWCapabilities.availableControls`, so
/// which knobs appear is a value the tests can assert rather than a shape buried in a `ViewBuilder`.
/// An unsupported adjustment remains visible but disabled: the user can distinguish a camera
/// limitation from a control that is missing from the product, without being offered a control that
/// the decoder would silently ignore.
///
/// **Four states, and the middle two are why this switches on `developPanelState`.** This used to be
/// `if let capabilities = viewModel.rawCapabilities { … } else { notRAW }`, which read the probe's
/// in-flight `nil` as "this file has no develop stage" and said exactly that, out loud, about a RAW —
/// for the 25–170 ms the probe takes, on every ←/→ step through a folder of them, since
/// `inspectorTab` was not reset on open. The active tab is now repaired when a new source makes
/// Develop unavailable. The distinction is drawn in the view model (`AppViewModel.DevelopPanelState`)
/// rather than here: this repo has no SwiftUI view tests, so a state that exists only inside a
/// `ViewBuilder` cannot be asserted.
struct DevelopInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            switch viewModel.developPanelState {
            case .ready(let capabilities):
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        ForEach(Array(DevelopControl.allCases.enumerated()), id: \.element) { offset, control in
                            controlRow(
                                control,
                                enabled: capabilities.supports(control),
                                sortPriority: Double(DevelopControl.allCases.count - offset)
                            )
                        }
                    }
                    .padding(16)
                }
            case .probing:
                probing
            case .noDevelopStage:
                notRAW
            case .noSupportedControls:
                noSupportedControls
            }
        }
    }

    private var header: some View {
        HStack {
            Text("RAW Develop").font(.headline)
            Spacer()
            Button("Reset") { viewModel.resetAllDevelop() }
                .buttonStyle(.link)
                .disabled(viewModel.document.rawDevelop.isNeutral)
        }
    }

    /// Shown for a RAW whose capability probe is still running.
    ///
    /// The header stays put — this file *does* have a develop stage, and the panel's identity should
    /// not blink out and back while a 25–170 ms question is answered — and only the control list is
    /// replaced, by a spinner. The alternative considered was keeping the previous image's controls
    /// on screen; it was rejected because their *values* are the previous file's per-image seeds
    /// (as-shot white balance, sharpening amount), so the panel would show numbers that are wrong
    /// for the picture on screen. A spinner claims nothing.
    private var probing: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the decoder's develop controls\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shown for a standard image. `RenderPipeline.developedSource` switches on `source.kind` and
    /// drops `rawDevelop` entirely for one, so offering the controls would be offering a lie.
    ///
    /// **Only ever reached once the answer is known.** Reaching it while the probe is in flight is
    /// the defect `developPanelState` exists to prevent — see this type's doc comment.
    private var notRAW: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.aperture")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No develop stage")
                .font(.headline)
            Text("Develop controls come from the RAW decoder. This image is already rendered.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSupportedControls: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.aperture")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No supported develop controls")
                .font(.headline)
            Text("This RAW decoder does not expose controls Lumo can edit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func controlRow(
        _ control: DevelopControl, enabled: Bool, sortPriority: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ResettableAdjustmentLabel(
                    title: control.title,
                    reset: {
                        if control == .whiteBalance {
                            viewModel.resetWhiteBalance()
                        } else {
                            viewModel.resetDevelop(control)
                        }
                    },
                    resetActionTitle: control == .whiteBalance
                        ? "Reset to As Shot" : "Reset to decoder default"
                )
                Spacer()
                if !control.isToggle {
                    Text(String(format: "%.2f", viewModel.developValue(for: control)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            if control.isToggle {
                Toggle(control.title, isOn: Binding(
                    get: { viewModel.developValue(for: control) != 0 },
                    set: { viewModel.developBinding(for: control).wrappedValue = $0 ? 1 : 0 }
                ))
                .labelsHidden()
                .accessibilityLabel(control.title)
                .accessibilityValue(viewModel.developValue(for: control) != 0 ? "On" : "Off")
                .accessibilitySortPriority(sortPriority)
            } else {
                Slider(
                    value: viewModel.developBinding(for: control),
                    in: control.range,
                    onEditingChanged: { editing in
                        if editing {
                            viewModel.beginPreviewInteraction()
                        } else {
                            viewModel.endPreviewInteraction()
                        }
                    }
                )
                .accessibilityLabel(control == .whiteBalance ? "White Balance Temperature" : control.title)
                .accessibilityValue(String(format: "%.2f", viewModel.developValue(for: control)))
                .accessibilitySortPriority(sortPriority)
                .accessibilityAction(named: Text(
                    control == .whiteBalance ? "Reset to As Shot" : "Reset to decoder default"
                )) {
                    if control == .whiteBalance {
                        viewModel.resetWhiteBalance()
                    } else {
                        viewModel.resetDevelop(control)
                    }
                }
                if control == .whiteBalance {
                    HStack {
                        Button("As Shot") { viewModel.resetWhiteBalance() }
                            .buttonStyle(.link)
                            .help("Restore this file's decoder white balance")
                        ResettableAdjustmentLabel(
                            title: "Tint",
                            reset: { viewModel.resetWhiteBalance(.tint) },
                            resetActionTitle: "Reset to As Shot"
                        )
                        Slider(
                            value: viewModel.developTintBinding(),
                            in: DevelopControl.tintRange,
                            onEditingChanged: { editing in
                                if editing {
                                    viewModel.beginPreviewInteraction()
                                } else {
                                    viewModel.endPreviewInteraction()
                                }
                            }
                        )
                        .accessibilityLabel("White Balance Tint")
                        .accessibilityValue(String(format: "%.2f", viewModel.developTintBinding().wrappedValue))
                        .accessibilitySortPriority(sortPriority - 0.5)
                    }
                }
            }
        }
        .opacity(enabled ? 1 : 0.55)
        .disabled(!enabled)
        .help(enabled ? "" : "Not supported by this RAW decoder")
    }
}
