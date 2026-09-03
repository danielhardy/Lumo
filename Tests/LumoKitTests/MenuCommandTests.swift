import SwiftUI
import XCTest
@testable import LumoKit

final class MenuCommandTests: XCTestCase {
    func testSettingsCommandComesFromTheNativeSettingsScene() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LumoKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let menuCommands = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/LumoKit/Views/MenuCommands.swift"),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Lumo/LumoApp.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(menuCommands.contains("SettingsLink()"))
        XCTAssertEqual(app.components(separatedBy: "\n        Settings {").count - 1, 1)
    }

    func testEditTransferShortcutsDoNotClaimStandardTextClipboardKeys() {
        let modifiers = LumoEditTransferShortcuts.modifiers

        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertTrue(modifiers.contains(.option))
        XCTAssertFalse(modifiers.contains(.shift))
        XCTAssertFalse(modifiers.contains(.control))
        XCTAssertEqual(LumoEditTransferShortcuts.copyKey, "c")
        XCTAssertEqual(LumoEditTransferShortcuts.pasteKey, "v")
    }

    func testLookFolderMenuUsesTheCanonicalLookRoute() {
        XCTAssertEqual(Notification.Name.chooseLookFolder.rawValue, "Lumo.chooseLookFolder")
        XCTAssertEqual(Notification.Name.importLook.rawValue, "Lumo.importLook")
    }
}
