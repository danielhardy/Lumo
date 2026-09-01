import SwiftUI

// The File menu and the notifications it posts. These live in LumoKit rather
// than beside `@main` so the executable target stays a thin entry point (and so
// the menu can be exercised from tests).

// MARK: - Commands

/// Lumo's File menu, replacing SwiftUI's default "New" group.
///
/// One of two entry points LumoKit exposes to the executable (the other is
/// `ContentView`). Each item posts a notification that `MenuCommandReceivers`
/// picks up on the view side — the menu bar is outside the view hierarchy, so
/// it can't reach the view model directly.
public struct LumoCommands: Commands {

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Image...") { post(.openImage) }
                .keyboardShortcut("o")

            Button("Choose Look Folder...") { post(.chooseLUTFolder) }
                .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            Button("Import from Photos...") { post(.importFromPhotos) }
                .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Open Source Folder...") { post(.openSourceFolder) }
                .keyboardShortcut("i", modifiers: [.command, .option])

            Button("Refresh Source Folder") { post(.refreshSourceFolder) }
                .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("Undo") { post(.undoEdit) }
                .keyboardShortcut("z", modifiers: [.command])
            Button("Redo") { post(.redoEdit) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button("Reset Photo") { post(.resetPhoto) }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Derive LUT from JPG…") { post(.deriveRecipe) }
                .keyboardShortcut("d")

            Divider()

            Button("Export...") { post(.exportImage) }
                .keyboardShortcut("s")

            Button("Export All...") { post(.exportAll) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

// MARK: - Receivers

/// Bridges the menu's notifications back to the view model.
struct MenuCommandReceivers: ViewModifier {
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openImage)) { _ in
                viewModel.openImageDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportImage)) { _ in
                viewModel.exportDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportAll)) { _ in
                viewModel.batchExportDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .chooseLUTFolder)) { _ in
                viewModel.chooseLUTFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importFromPhotos)) { _ in
                viewModel.importFromPhotos()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSourceFolder)) { _ in
                viewModel.chooseSourceFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .refreshSourceFolder)) { _ in
                viewModel.refreshSource()
            }
            .onReceive(NotificationCenter.default.publisher(for: .undoEdit)) { _ in
                viewModel.undo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .redoEdit)) { _ in
                viewModel.redo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetPhoto)) { _ in
                viewModel.resetPhoto()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deriveRecipe)) { _ in
                viewModel.presentRecipeExtractor()
            }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openImage = Notification.Name("Lumo.openImage")
    static let exportImage = Notification.Name("Lumo.exportImage")
    static let exportAll = Notification.Name("Lumo.exportAll")
    static let chooseLUTFolder = Notification.Name("Lumo.chooseLUTFolder")
    static let importFromPhotos = Notification.Name("Lumo.importFromPhotos")
    static let openSourceFolder = Notification.Name("Lumo.openSourceFolder")
    static let refreshSourceFolder = Notification.Name("Lumo.refreshSourceFolder")
    static let undoEdit = Notification.Name("Lumo.undoEdit")
    static let redoEdit = Notification.Name("Lumo.redoEdit")
    static let resetPhoto = Notification.Name("Lumo.resetPhoto")
    static let deriveRecipe = Notification.Name("Lumo.deriveRecipe")
}
