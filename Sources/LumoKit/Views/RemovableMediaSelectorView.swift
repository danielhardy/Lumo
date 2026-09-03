import SwiftUI
import AppKit

/// Image-first picker for a mounted removable volume. It has no folder-navigation affordance on
/// purpose: the volume has already been selected from the Import menu and this sheet is only for
/// choosing files and explicitly adding them to the library.
struct RemovableMediaSelectorView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if viewModel.isRemovableMediaScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning \(viewModel.removableMediaVolume?.name ?? "volume")…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.removableMediaFiles.isEmpty {
                ContentUnavailableView(
                    "No Supported Images",
                    systemImage: "externaldrive",
                    description: Text("This volume has no readable images Lumo can open.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fileList
            }
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 500)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(viewModel.removableMediaVolume?.name ?? "Removable Media", systemImage: "externaldrive.connected.to.line.below")
                .font(.headline)
            Spacer()
            if !viewModel.removableMediaFiles.isEmpty {
                Text("\(viewModel.removableMediaSelection.count) of \(viewModel.removableMediaFiles.count) selected")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(16)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Select All") { viewModel.selectAllRemovableMedia() }
                Button("Select None") { viewModel.selectNoRemovableMedia() }
                Spacer()
                Text("Images are added from the card; source files are not changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if !viewModel.removableMediaWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.removableMediaWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            List(viewModel.removableMediaFiles) { file in
                Button {
                    viewModel.toggleRemovableMediaSelection(file)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.removableMediaSelection.contains(file)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(viewModel.removableMediaSelection.contains(file)
                                             ? Color.accentColor : Color.secondary)
                        RemovableMediaThumbnail(url: file.url)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.filename)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                if !file.orientationLabel.isEmpty {
                                    Label(file.orientationLabel, systemImage: "rotate.right")
                                }
                                if let summary = file.metadataSummary {
                                    Text(summary)
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(file.filename)
                .accessibilityValue(viewModel.removableMediaSelection.contains(file) ? "Selected" : "Not selected")
            }
        }
    }

    private var footer: some View {
        HStack {
            if let progress = viewModel.removableMediaImportProgress {
                ProgressView(value: progress.fraction)
                    .frame(width: 130)
                Text(progress.cancelled
                     ? "Import cancelled"
                     : "Imported \(progress.imported), skipped \(progress.skipped)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { viewModel.cancelRemovableMediaImport() }
                .keyboardShortcut(.cancelAction)
            Button("Import Selected to Library") { viewModel.importSelectedRemovableMedia() }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isRemovableMediaScanning || viewModel.selectedRemovableMediaFiles.isEmpty)
        }
        .padding(16)
    }
}

private struct RemovableMediaThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay { ProgressView().scaleEffect(0.55) }
            }
        }
        .frame(width: 64, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: url) {
            image = await Task.detached(priority: .utility) {
                Thumbnails.generate(from: url, maxPixelSize: 128)
            }.value
        }
    }
}
