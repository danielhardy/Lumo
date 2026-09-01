import SwiftUI

// The bar along the bottom of the window: current status on the left, a
// reminder of the keys that do something on the right.

struct StatusBar: View {
    @ObservedObject var viewModel: AppViewModel
    var onCancelImport: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            // Status message
            if let progress = viewModel.photosImportProgress {
                ProgressView(value: progress.fraction)
                    .frame(width: 110)
                    .controlSize(.small)
                Text("\(progress.phase.label) \(progress.processed)/\(progress.total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 8)
                Button("Cancel") { onCancelImport() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .padding(.leading, 8)
            } else {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Hints
            HStack(spacing: 12) {
                KeyHint(key: "↑↓", label: "audition Looks")
                if viewModel.collection.isActive {
                    KeyHint(key: "←→", label: "cycle images")
                    KeyHint(key: "P/X", label: "pick/reject")
                    KeyHint(key: "0–5", label: "rate")
                }
                KeyHint(key: "V", label: viewModel.isSideBySideVisible ? "single view" : "side-by-side")
                KeyHint(key: "Space", label: "compare")
                KeyHint(key: "⌘S", label: "export")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Text(label)
                .font(.caption2)
                .foregroundColor(Color(nsColor: .quaternaryLabelColor))
        }
    }
}
