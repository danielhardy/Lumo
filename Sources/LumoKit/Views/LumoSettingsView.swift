import SwiftUI
import AppKit

/// The app-wide Settings surface. Folder defaults are intentionally separate from the currently
/// open source/Look folders: changing one changes where a future panel starts, not existing files.
public struct LumoSettingsView: View {
    @ObservedObject private var settings: LumoSettings
    @State private var sourceTestMessage = ""
    @State private var exportTestMessage = ""

    public init(settings: LumoSettings) {
        _settings = ObservedObject(wrappedValue: settings)
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Always dark mode", isOn: $settings.alwaysDarkMode)
                    .accessibilityLabel("Always dark mode")
                    .accessibilityHint("Use dark appearance even when macOS is set to light mode")
            } header: {
                Text("Appearance")
            } footer: {
                Text("When off, Lumo follows the macOS appearance setting.")
            }

            folderSection(
                kind: .source,
                status: settings.sourceFolderStatus,
                testMessage: $sourceTestMessage
            )
            folderSection(
                kind: .export,
                status: settings.exportFolderStatus,
                testMessage: $exportTestMessage
            )

            Section {
                HStack {
                    Label("User Looks and LUTs", systemImage: "wand.and.stars")
                    Spacer()
                    Text(settings.userLookFolderURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("User-created and imported Looks are stored here. Bundled Looks, if added later, are separate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reveal User Looks Folder") {
                    if !settings.revealUserLookFolder() {
                        sourceTestMessage = "The User Looks folder could not be opened."
                    }
                }
                .accessibilityLabel("Reveal User Looks folder")
                .accessibilityHint("Open the canonical folder for user-created and imported Looks")
            } header: {
                Text("Look storage")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560)
        .task {
            settings.refreshFolderStatus()
        }
    }

    @ViewBuilder
    private func folderSection(
        kind: LumoFolderKind,
        status: LumoFolderStatus,
        testMessage: Binding<String>
    ) -> some View {
        Section {
            HStack {
                Label(kind.title, systemImage: "folder")
                Spacer()
                Text(statusLabel(status))
                    .foregroundStyle(status.isAvailable ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }
            if let displayName = status.displayName {
                Text(displayName)
                    .font(.callout)
                    .accessibilityLabel("Configured folder: " + displayName)
            } else {
                Text("Not configured — Lumo will use the folder you choose each time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Choose…") { chooseFolder(kind) }
                    .accessibilityLabel("Choose " + kind.title)
                Button("Test") {
                    testMessage.wrappedValue = settings.testDefaultFolder(kind).message
                }
                .disabled(!status.isConfigured)
                .accessibilityLabel("Test " + kind.title)
                Button("Reset") { settings.resetDefaultFolder(kind) }
                    .disabled(!status.isConfigured)
                    .accessibilityLabel("Reset " + kind.title)
                Spacer()
            }
            if !testMessage.wrappedValue.isEmpty {
                Text(testMessage.wrappedValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(testMessage.wrappedValue)
            }
        } header: {
            Text(kind == .source ? "Import defaults" : "Export defaults")
        } footer: {
            Text(kind == .source
                 ? "Used as the starting location for future image and source-folder panels. It does not change the open source folder."
                 : "Used as the starting location for future exports. It does not move or rewrite existing files.")
        }
    }

    private func statusLabel(_ status: LumoFolderStatus) -> String {
        switch status.availability {
        case .notConfigured: return "Not set"
        case .available: return "Ready"
        case .unavailable: return "Unavailable — choose again"
        case .inaccessible: return "Access needed — choose again"
        }
    }

    private func chooseFolder(_ kind: LumoFolderKind) {
        let panel = NSOpenPanel()
        panel.title = "Choose " + kind.title
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = kind == .export
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard settings.setDefaultFolder(url, for: kind) else {
            let message = "Lumo could not save access to " + url.lastPathComponent
                + ". Choose the folder again to grant permission."
            if kind == .source { sourceTestMessage = message } else { exportTestMessage = message }
            return
        }
        if kind == .source { sourceTestMessage = "Ready for future imports." }
        else { exportTestMessage = "Ready for future exports." }
    }
}
