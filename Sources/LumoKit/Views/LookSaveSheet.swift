import SwiftUI

/// Reviews the versioned LUT support matrix before the user chooses a destination.
struct LookSaveSheet: View {
    @ObservedObject var coordinator: LookSaveCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Save as Look/LUT")
                    .font(.title2.bold())
                Text("Save the active photo's verified global RGB edits as a standard .cube Look.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField("Look name", text: $coordinator.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Look name")

            if coordinator.isConverting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Sampling the global edit stages…")
                        .foregroundStyle(.secondary)
                }
            } else if let conversion = coordinator.conversion {
                conversionDetails(conversion)
            }

            if let saveError = coordinator.saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel", role: .cancel) {
                    coordinator.dismiss()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save .cube…") { coordinator.saveDialog() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(coordinator.isConverting || coordinator.conversion == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .frame(minHeight: 360)
        .background(LumoTheme.windowBackground)
    }

    private func conversionDetails(_ conversion: LookLUTConversion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Support matrix v\(conversion.supportMatrix.version)")
                    .font(.headline)
                Spacer()
                Text("\(conversion.size)³  •  \(conversion.workingSpace.rawValue)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(conversion.supportMatrix.hasOmissions
                 ? "The following edits will be omitted. Review them before saving."
                 : "All active edits are verified global RGB stages and will be included.")
                .font(.callout)
                .foregroundStyle(conversion.supportMatrix.hasOmissions ? .orange : .secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(conversion.supportMatrix.entries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: entry.disposition == .included ? "checkmark.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(entry.disposition == .included ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).font(.callout.weight(.medium))
                                Text(entry.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if conversion.supportMatrix.entries.isEmpty {
                        Text("No active edits; an identity Look will be saved.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 170)

            Text("Domain/range: 0.0–1.0. The .cube preserves global color/tone only; it does not reproduce RAW development, crop/rotation, masking, vignette, grain, or other spatial/source-dependent edits. Tolerance: ±\(String(format: "%.3f", conversion.verification.tolerance)) per channel.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
