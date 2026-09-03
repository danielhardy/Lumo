import SwiftUI

// The File menu and the notifications it posts. These live in LumoKit rather
// than beside `@main` so the executable target stays a thin entry point (and so
// the menu can be exercised from tests).

// MARK: - Commands

/// The edit-transfer shortcuts deliberately include Option so they do not compete with AppKit's
/// standard Command-C/Command-V actions when a text field owns the first responder.
enum LumoEditTransferShortcuts {
    static let modifiers: EventModifiers = [.command, .option]
    static let copyKey: KeyEquivalent = "c"
    static let pasteKey: KeyEquivalent = "v"
}

/// Lumo's File menu, replacing SwiftUI's default "New" group.
///
/// One of two entry points LumoKit exposes to the executable (the other is
/// `ContentView`). Each item posts a notification that `MenuCommandReceivers`
/// picks up on the view side — the menu bar is outside the view hierarchy, so
/// it can't reach the view model directly.
public struct LumoCommands: Commands {

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            SettingsLink()
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Image...") { post(.openImage) }
                .keyboardShortcut("o")

            Button("Choose Look Folder...") { post(.chooseLookFolder) }
                .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Import Look...") { post(.importLook) }
                .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button("Import from Photos...") { post(.importFromPhotos) }
                .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Open Source Folder...") { post(.openSourceFolder) }
                .keyboardShortcut("i", modifiers: [.command, .option])

            Button("Import from Removable Media...") { post(.importFromRemovableMedia) }

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

            Button("Copy All Edits") { post(.copyAllEdits) }
                .keyboardShortcut(
                    LumoEditTransferShortcuts.copyKey,
                    modifiers: LumoEditTransferShortcuts.modifiers
                )
            Button("Paste Edits") { post(.pasteEdits) }
                .keyboardShortcut(
                    LumoEditTransferShortcuts.pasteKey,
                    modifiers: LumoEditTransferShortcuts.modifiers
                )

            Divider()

            Button("Derive Look from JPG…") { post(.deriveRecipe) }
                .keyboardShortcut("d")

            Button("Save as Look/LUT…") { post(.saveLook) }

            Divider()

            Button("Export...") { post(.exportImage) }
                .keyboardShortcut("s")

            Button("Export Selected...") { post(.exportSelected) }
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
            .onReceive(NotificationCenter.default.publisher(for: .exportSelected)) { _ in
                viewModel.exportSelectedDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .chooseLookFolder)) { _ in
                viewModel.chooseLookFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importLook)) { _ in
                viewModel.chooseLookFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importFromPhotos)) { _ in
                viewModel.importFromPhotos()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSourceFolder)) { _ in
                viewModel.chooseSourceFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importFromRemovableMedia)) { _ in
                viewModel.importFromRemovableMedia()
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
            .onReceive(NotificationCenter.default.publisher(for: .copyAllEdits)) { _ in
                viewModel.copyAllEdits()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pasteEdits)) { _ in
                viewModel.pasteEdits()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deriveRecipe)) { _ in
                viewModel.presentRecipeExtractor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveLook)) { _ in
                viewModel.presentSaveLook()
            }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openImage = Notification.Name("Lumo.openImage")
    static let exportImage = Notification.Name("Lumo.exportImage")
    static let exportSelected = Notification.Name("Lumo.exportSelected")
    /// Compatibility name for callers from the pre-selection export flow.
    static let exportAll = exportSelected
    static let chooseLookFolder = Notification.Name("Lumo.chooseLookFolder")
    static let importLook = Notification.Name("Lumo.importLook")
    static let importFromPhotos = Notification.Name("Lumo.importFromPhotos")
    static let openSourceFolder = Notification.Name("Lumo.openSourceFolder")
    static let importFromRemovableMedia = Notification.Name("Lumo.importFromRemovableMedia")
    static let refreshSourceFolder = Notification.Name("Lumo.refreshSourceFolder")
    static let undoEdit = Notification.Name("Lumo.undoEdit")
    static let redoEdit = Notification.Name("Lumo.redoEdit")
    static let resetPhoto = Notification.Name("Lumo.resetPhoto")
    static let copyAllEdits = Notification.Name("Lumo.copyAllEdits")
    static let pasteEdits = Notification.Name("Lumo.pasteEdits")
    static let deriveRecipe = Notification.Name("Lumo.deriveRecipe")
    static let saveLook = Notification.Name("Lumo.saveLook")
}
