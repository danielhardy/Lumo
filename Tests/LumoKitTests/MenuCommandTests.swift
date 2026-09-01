import SwiftUI
import XCTest
@testable import LumoKit

final class MenuCommandTests: XCTestCase {
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
