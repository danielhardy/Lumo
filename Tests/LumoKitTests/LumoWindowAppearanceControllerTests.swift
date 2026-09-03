import AppKit
import XCTest
@testable import LumoKit

@MainActor
final class LumoWindowAppearanceControllerTests: XCTestCase {

    private func makeSettings(alwaysDarkMode: Bool = false) -> LumoSettings {
        let suite = "LumoWindowAppearanceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = LumoSettings(preferences: defaults)
        settings.alwaysDarkMode = alwaysDarkMode
        return settings
    }

    func testPreferenceMapsToSystemOrDarkMode() {
        XCTAssertEqual(LumoAppearanceMode(alwaysDarkMode: false), .system)
        XCTAssertEqual(LumoAppearanceMode(alwaysDarkMode: true), .dark)
    }

    func testWindowOverridePropagatesAndClearsForMacOSFollowingMode() {
        let settings = makeSettings()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let controller = LumoWindowAppearanceController(settings: settings)

        controller.applyCurrentAppearance(to: [window])
        XCTAssertNil(window.appearance)

        settings.alwaysDarkMode = true
        controller.applyCurrentAppearance(to: [window])
        XCTAssertEqual(window.appearance?.name, .darkAqua)

        settings.alwaysDarkMode = false
        controller.applyCurrentAppearance(to: [window])
        XCTAssertNil(window.appearance)
        controller.stop()
    }

    func testStartedControllerUpdatesExistingWindowAfterPreferenceChange() async {
        let settings = makeSettings()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let controller = LumoWindowAppearanceController(
            settings: settings,
            windowProvider: { [window] }
        )
        controller.start()

        settings.alwaysDarkMode = true
        await Task.yield()
        XCTAssertEqual(window.appearance?.name, .darkAqua)

        settings.alwaysDarkMode = false
        await Task.yield()
        XCTAssertNil(window.appearance)
        controller.stop()
    }
}
