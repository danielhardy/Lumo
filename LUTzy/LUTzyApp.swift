import SwiftUI

@main
struct LUTzyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Replace default file menu items
            CommandGroup(replacing: .newItem) {
                Button("Open Image...") {
                    NotificationCenter.default.post(name: .openImage, object: nil)
                }
                .keyboardShortcut("o")

                Button("Choose LUT Folder...") {
                    NotificationCenter.default.post(name: .chooseLUTFolder, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Import from Photos...") {
                    NotificationCenter.default.post(name: .importFromPhotos, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Import Folder...") {
                    NotificationCenter.default.post(name: .importFolder, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Divider()

                Button("Derive LUT from JPG…") {
                    NotificationCenter.default.post(name: .deriveRecipe, object: nil)
                }
                .keyboardShortcut("d")

                Divider()

                Button("Export...") {
                    NotificationCenter.default.post(name: .exportImage, object: nil)
                }
                .keyboardShortcut("s")
            }
        }
    }
}
