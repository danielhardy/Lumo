import AppKit
import Combine

/// The app-shell appearance requested by the user. `.system` deliberately maps to no
/// window override so AppKit can follow the current macOS appearance.
public enum LumoAppearanceMode: Equatable, Sendable {
    case system
    case dark

    public init(alwaysDarkMode: Bool) {
        self = alwaysDarkMode ? .dark : .system
    }
}

/// Applies the app-wide appearance preference to every SwiftUI-hosting window and native chrome.
///
/// `preferredColorScheme` is scoped to a SwiftUI view hierarchy and does not reliably
/// update an already-created sibling scene (the main window and Settings are separate
/// scenes). The controller therefore owns both the application and window-level overrides. The
/// application override is required for the title bar and traffic-light chrome of a SwiftUI
/// `Settings` scene, which do not reliably inherit an individual window's override. A `nil`
/// appearance restores macOS-following behavior instead of hard-coding a light fallback.
@MainActor
public final class LumoWindowAppearanceController {
    private let settings: LumoSettings
    private let windowProvider: @MainActor () -> [NSWindow]
    private let applicationAppearanceApplier: @MainActor (NSAppearance?) -> Void
    /// The incoming publisher value is authoritative while `@Published` is in its `willSet`
    /// phase. Keeping it separately prevents a later window notification from re-reading the
    /// stale property and reapplying dark mode during an off transition.
    private var desiredAlwaysDarkMode: Bool
    private var settingsCancellable: AnyCancellable?
    private var windowObservers: [NSObjectProtocol] = []

    public init(
        settings: LumoSettings,
        windowProvider: @escaping @MainActor () -> [NSWindow] = { NSApp.windows },
        applicationAppearanceApplier: @escaping @MainActor (NSAppearance?) -> Void = { appearance in
            NSApp.appearance = appearance
        }
    ) {
        self.settings = settings
        self.windowProvider = windowProvider
        self.applicationAppearanceApplier = applicationAppearanceApplier
        self.desiredAlwaysDarkMode = settings.alwaysDarkMode
    }

    /// Begin observing the preference and newly presented windows. Calling this more than
    /// once is harmless, which keeps app launch and test setup idempotent.
    public func start() {
        guard settingsCancellable == nil else { return }

        // Subscribe to the value rather than `objectWillChange`. The latter only says that some
        // setting is changing, and the previous implementation had to enqueue another main-actor
        // task before it could read the new value. That makes an already-open window visibly lag
        // behind the Settings toggle when the main actor is busy. `@Published` sends the incoming
        // value while its property is changing, so use that value directly instead of reading the
        // still-old stored property.
        settingsCancellable = settings.$alwaysDarkMode
            .dropFirst()
            .sink { [weak self] alwaysDarkMode in
                guard let self else { return }
                self.desiredAlwaysDarkMode = alwaysDarkMode
                self.applyAppearance(alwaysDarkMode: alwaysDarkMode, includesApplication: true)
            }

        let notificationCenter = NotificationCenter.default
        for name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
        ] {
            windowObservers.append(
                notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.applyCurrentAppearance()
                    }
                }
            )
        }

        applyCurrentAppearance()
    }

    /// Stop observation explicitly. This is intentionally not done from `deinit`: Swift 6
    /// deinitializers are nonisolated, while NotificationCenter and AppKit require main-actor
    /// access.
    public func stop() {
        settingsCancellable?.cancel()
        settingsCancellable = nil
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }

    /// Apply the current preference to a supplied window set. The injectable set makes the
    /// propagation seam testable without requiring a launched application or a real window.
    public func applyCurrentAppearance(to windows: [NSWindow]) {
        applyAppearance(alwaysDarkMode: settings.alwaysDarkMode, to: windows)
    }

    private func applyAppearance(
        alwaysDarkMode: Bool,
        to windows: [NSWindow]? = nil,
        includesApplication: Bool = false
    ) {
        let appearance = NSAppearance(named: .darkAqua)
        let mode = LumoAppearanceMode(alwaysDarkMode: alwaysDarkMode)
        if includesApplication {
            // A window appearance colors SwiftUI content, but Settings' native title bar belongs
            // to the application chrome. Apply the same override there before visiting windows.
            applicationAppearanceApplier(mode == .dark ? appearance : nil)
        }
        for window in windows ?? windowProvider() {
            window.appearance = mode == .dark ? appearance : nil
        }
    }

    private func applyCurrentAppearance() {
        applyAppearance(alwaysDarkMode: desiredAlwaysDarkMode, includesApplication: true)
    }
}
