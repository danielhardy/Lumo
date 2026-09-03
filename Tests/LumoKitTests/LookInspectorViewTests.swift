import XCTest
@testable import LumoKit

/// The Look inspector's visual states are intentionally represented by a small presentation
/// matrix. These tests keep the empty, scanning, unavailable-folder, and missing-reference copy
/// from regressing while the actual view remains covered by manual visual/accessibility QA.
final class LookInspectorViewTests: XCTestCase {
    func testEmptyStatePresentationMatrix() {
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: true,
                lookCount: 0,
                folderConfigured: true,
                scanError: nil
            ),
            .scanning
        )
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: false,
                lookCount: 0,
                folderConfigured: true,
                scanError: "Can't find the selected folder"
            ),
            .folderUnavailable
        )
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: false,
                lookCount: 0,
                folderConfigured: true,
                scanError: nil,
                hasMissingReference: true
            ),
            .missingReference
        )
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: false,
                lookCount: 0,
                folderConfigured: true,
                scanError: nil
            ),
            .emptyFolder
        )
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: false,
                lookCount: 0,
                folderConfigured: false,
                scanError: nil
            ),
            .firstLook
        )
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: false,
                lookCount: 1,
                folderConfigured: true,
                scanError: nil
            ),
            .populated
        )
    }

    func testFirstLookCopyExplainsExternalSources() {
        let state = LookInspectorEmptyState.firstLook

        XCTAssertEqual(state.title, "Bring in your first Look")
        XCTAssertTrue(state.message.contains(".cube"))
        XCTAssertTrue(state.message.contains(".look"))
        XCTAssertTrue(state.message.contains("starter library"))
    }
}
