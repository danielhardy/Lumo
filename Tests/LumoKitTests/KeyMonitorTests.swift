import XCTest
import AppKit
@testable import LumoKit

/// The one behaviour Step 8 changed.
///
/// `KeyMonitor` removed its `NSEvent` monitor in `deinit`. Swift 6 language mode makes a `deinit`
/// `nonisolated` — it can run on any thread — so it may not touch the `Any?` token AppKit hands back,
/// which is not `Sendable`. The escape hatches are `nonisolated(unsafe)` and `@unchecked Sendable`,
/// and this module uses neither, so teardown became an explicit `stop()` on the main actor.
///
/// That is the *better* shape regardless of the compiler: `NSEvent.removeMonitor` is an AppKit call
/// that wants the main thread, and reaching it from a `deinit` that could run anywhere was always
/// the wrong place for it.
///
/// **What this cannot cover:** that `KeyboardShortcuts.onDisappear` actually calls `stop()`. That is
/// a SwiftUI view body, and `docs/CODE_REVIEW.md` §5 already records that views are exercised only
/// insofar as the view model is. The lifecycle contract below is the testable half; the wiring was
/// checked by hand in the running app.
@MainActor
final class KeyMonitorTests: XCTestCase {

    /// Records what was torn down. `isMonitoring` on its own is not enough: it reports whether the
    /// token was cleared, and a `stop()` that cleared the token *without* calling
    /// `NSEvent.removeMonitor` would leak the monitor and still pass. A mutation proved exactly that,
    /// which is why `KeyMonitor` takes the removal as a parameter.
    private final class Removals {
        var tokens: [Any] = []
        var count: Int { tokens.count }
    }

    private func makeMonitor(_ removals: Removals) -> KeyMonitor {
        KeyMonitor(
            viewModel: AppViewModel(engine: FakeRenderEngine()),
            removeMonitor: { removals.tokens.append($0) }
        )
    }

    func testAMonitorIsInstalledOnInitAndRemovedByStop() {
        let removals = Removals()
        let monitor = makeMonitor(removals)
        XCTAssertTrue(monitor.isMonitoring, "the monitor should be live as soon as it exists")
        XCTAssertEqual(removals.count, 0, "nothing should have been torn down yet")

        monitor.stop()
        XCTAssertFalse(monitor.isMonitoring, "stop() must clear the token")
        XCTAssertEqual(removals.count, 1, "…and must actually remove the monitor, not just forget it")
    }

    /// `onDisappear` can fire more than once, and a released view could stop a monitor that a
    /// later one already stopped. `NSEvent.removeMonitor` on a stale token is not something to find
    /// out about at runtime.
    func testStopIsIdempotent() {
        let removals = Removals()
        let monitor = makeMonitor(removals)
        monitor.stop()
        monitor.stop()
        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertEqual(removals.count, 1, "a second stop() must not remove a stale token")
    }

    /// Dropping the last reference without stopping must not crash — it simply leaks the monitor
    /// until the process exits, which is the trade the `deinit` removal makes explicit.
    func testDroppingAMonitorWithoutStoppingIsSafe() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        for _ in 0..<3 {
            let monitor = KeyMonitor(viewModel: viewModel)
            XCTAssertTrue(monitor.isMonitoring)
        }
        // Reaching here at all is the assertion: a `deinit` that still touched AppKit state from
        // an arbitrary thread is what Swift 6 was objecting to.
        XCTAssertTrue(true)
    }

    func testGlobalShortcutsDeferToTextInputAndSystemModifiers() {
        XCTAssertTrue(KeyMonitorPolicy.textInputOwnsKeyboard(NSText()))
        XCTAssertFalse(KeyMonitorPolicy.textInputOwnsKeyboard(NSView()))

        XCTAssertFalse(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSText()))
        XCTAssertFalse(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSTextField()))
        XCTAssertFalse(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSSlider()))
        XCTAssertFalse(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSButton()))
        XCTAssertFalse(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSSegmentedControl()))
        XCTAssertTrue(KeyMonitorPolicy.globalShortcutsOwnKeyboard(NSView()))
        XCTAssertTrue(KeyMonitorPolicy.globalShortcutsOwnKeyboard(nil))

        XCTAssertTrue(KeyMonitorPolicy.isPlainSpace(modifiers: []))
        XCTAssertFalse(KeyMonitorPolicy.isPlainSpace(modifiers: .shift))
        XCTAssertFalse(KeyMonitorPolicy.isPlainSpace(modifiers: .option))
        XCTAssertFalse(KeyMonitorPolicy.isPlainSpace(modifiers: .control))

        XCTAssertFalse(KeyMonitorPolicy.hasSystemModifier(.shift))
        XCTAssertTrue(KeyMonitorPolicy.hasSystemModifier(.option))
        XCTAssertTrue(KeyMonitorPolicy.hasSystemModifier(.control))
        XCTAssertTrue(KeyMonitorPolicy.hasSystemModifier(.command))
    }
}
