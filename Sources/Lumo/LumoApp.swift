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
    private var terminationFlushInProgress = false

    override init() {
        viewModel = AppViewModel()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationFlushInProgress else { return .terminateLater }
        terminationFlushInProgress = true
        Task { @MainActor [viewModel] in
            await viewModel.flushPendingWrites()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
    }
}
