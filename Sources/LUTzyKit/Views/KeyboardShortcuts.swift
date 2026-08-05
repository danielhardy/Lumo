import SwiftUI
import AppKit

//
// SwiftUI's `.onKeyPress` modifier only fires when the modified view (or a
// descendant) has focus. Inside a NavigationSplitView the sidebar list eats
// focus when clicked and the detail pane has nothing focusable by default, so
// `.onKeyPress` was effectively never firing. We use an NSEvent local monitor
// instead, which catches every key event at the window level regardless of
// which subview has focus. Menu shortcuts (⌘-anything) still go through the
// standard menu system — we explicitly let those events pass through.

struct KeyboardShortcuts: ViewModifier {
    @ObservedObject var viewModel: AppViewModel
    @State private var monitor: KeyMonitor?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if monitor == nil {
                    monitor = KeyMonitor(viewModel: viewModel)
                }
            }
            .onDisappear {
                monitor = nil
            }
    }
}

/// Owns an NSEvent local monitor for the lifetime of the main content view.
/// Class so we can clean up the monitor in `deinit`.
@MainActor
final class KeyMonitor {
    private var token: Any?
    private weak var viewModel: AppViewModel?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            return self?.handle(event) ?? event
        }
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let vm = viewModel else { return event }

        // If a sheet is up, let the sheet's text fields and buttons handle keys.
        if vm.derive.isSheetPresented { return event }

        // Don't hijack keys while editing text (the search field, etc.) — a
        // focused SwiftUI TextField makes the window's field editor (an NSText)
        // the first responder.
        if NSApp.keyWindow?.firstResponder is NSText { return event }

        // Don't consume Command-modified events — those belong to the menu bar.
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) { return event }

        let isDown = event.type == .keyDown

        // Hardware key codes (US layout independent for arrows/space).
        // ↑/↓ cycle LUTs; ←/→ step through the source files.
        switch event.keyCode {
        case 49:  // Space — hold to compare original
            vm.showOriginal(isDown)
            return nil
        case 126: // Up arrow — previous LUT
            if isDown { vm.selectPreviousLUT() }
            return nil
        case 125: // Down arrow — next LUT
            if isDown { vm.selectNextLUT() }
            return nil
        case 123: // Left arrow — previous image
            guard vm.collection.isActive else { return event }
            if isDown { vm.selectPreviousImage() }
            return nil
        case 124: // Right arrow — next image
            guard vm.collection.isActive else { return event }
            if isDown { vm.selectNextImage() }
            return nil
        default:
            break
        }

        // Character keys (key-down only)
        guard isDown, let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return event
        }
        switch chars {
        case "v":
            vm.toggleSideBySide()
            return nil
        case "[":
            guard vm.collection.isActive else { return event }
            vm.selectPreviousImage()
            return nil
        case "]":
            guard vm.collection.isActive else { return event }
            vm.selectNextImage()
            return nil
        default:
            return event
        }
    }
}
