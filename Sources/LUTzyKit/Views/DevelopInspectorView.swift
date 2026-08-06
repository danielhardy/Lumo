import SwiftUI

/// RAW develop controls, gated per image on what the file's decoder actually supports.
///
/// The control list is not written out here — it comes from `RAWCapabilities.availableControls`, so
/// which knobs appear is a value the tests can assert rather than a shape buried in a `ViewBuilder`.
/// An unsupported adjustment is **absent**, not greyed out: absence reads as "this camera's decoder
/// does not do that", where a disabled slider reads as "you did something wrong".
struct DevelopInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if let capabilities = viewModel.rawCapabilities {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        ForEach(capabilities.availableControls, id: \.self) { control in
                            controlRow(control)
                        }
                    }
                    .padding(16)
                }
            } else {
                notRAW
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

    /// Shown for a standard image. `RenderPipeline.developedSource` switches on `source.kind` and
    /// drops `rawDevelop` entirely for one, so offering the controls would be offering a lie.
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

    @ViewBuilder
    private func controlRow(_ control: DevelopControl) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(control.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !AppViewModel.isToggle(control) {
                    Text(String(format: "%.2f", viewModel.developValue(for: control)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button {
                    viewModel.resetDevelop(control)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Reset to the decoder's default")
            }

            if AppViewModel.isToggle(control) {
                Toggle(control.title, isOn: Binding(
                    get: { viewModel.developValue(for: control) != 0 },
                    set: { viewModel.developBinding(for: control).wrappedValue = $0 ? 1 : 0 }
                ))
                .labelsHidden()
            } else {
                Slider(
                    value: viewModel.developBinding(for: control),
                    in: AppViewModel.range(for: control)
                )
                if control == .whiteBalance {
                    HStack {
                        Text("Tint").font(.caption2).foregroundStyle(.secondary)
                        Slider(value: viewModel.developTintBinding(), in: -150...150)
                    }
                }
            }
        }
    }
}
