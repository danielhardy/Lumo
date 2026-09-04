import SwiftUI
import AppKit
import LumoKit

// The whole app lives in LumoKit; this target is only the entry point, so the
// code can be unit-tested (`@testable` cannot import an executable target).

/// Forces normal foreground-app activation. When Lumo is launched as a bare
/// Swift Package executable (e.g. `swift run`, or running the SPM target from
/// Xcode), there is no app bundle / Info.plist, so macOS starts it as a
/// background process: no Dock icon, not in ⌘-Tab, and the window never comes
/// to the front. Setting `.regular` + activating makes the window appear
/// reliably. This is a no-op once Lumo runs as a properly bundled `.app`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel: AppViewModel
    private let appearanceController: LumoWindowAppearanceController
    private var terminationFlushInProgress = false

    override init() {
        let viewModel = AppViewModel(includeBundledLooks: true)
        self.viewModel = viewModel
        self.appearanceController = LumoWindowAppearanceController(settings: viewModel.settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appearanceController.start()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationFlushInProgress else { return .terminateLater }
        terminationFlushInProgress = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await viewModel.flushPendingWrites()
            await handleTerminationFlushResult(result, sender: sender)
        }
        return .terminateLater
    }

    private func handleTerminationFlushResult(
        _ result: PersistenceFlushResult,
        sender: NSApplication
    ) async {
        guard case .success = result else {
            let alert = NSAlert()
            alert.messageText = "Couldn’t save edits before quitting"
            alert.informativeText = terminationFailureMessage(for: result)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Retry Saving")
            alert.addButton(withTitle: "Quit Without Saving")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                terminationFlushInProgress = false
                startTerminationFlush(sender)
            case .alertSecondButtonReturn:
                await viewModel.discardPendingWrites()
                terminationFlushInProgress = false
                sender.reply(toApplicationShouldTerminate: true)
            default:
                terminationFlushInProgress = false
                sender.reply(toApplicationShouldTerminate: false)
            }
            return
        }

        sender.reply(toApplicationShouldTerminate: true)
    }

    private func startTerminationFlush(_ sender: NSApplication) {
        terminationFlushInProgress = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await viewModel.flushPendingWrites()
            await handleTerminationFlushResult(result, sender: sender)
        }
    }

    private func terminationFailureMessage(for result: PersistenceFlushResult) -> String {
        switch result {
        case .failure(let detail):
            return "\(detail)\n\nRetry saving, quit without saving these edits, or cancel quitting."
        case .cancelled:
            return "Saving edits was cancelled before all changes were written.\n\nRetry saving, quit without saving these edits, or cancel quitting."
        case .success:
            return "All edits were saved."
        }
    }
}

@main
struct LumoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: appDelegate.viewModel)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands { LumoCommands() }

        Settings {
            LumoSettingsView(settings: appDelegate.viewModel.settings)
        }
    }
}
