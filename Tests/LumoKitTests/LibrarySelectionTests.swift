import XCTest
@testable import LumoKit

final class LibrarySelectionTests: XCTestCase {
    private let ids = (0..<10).map { PhotoAssetID(rawValue: "photo-\($0)") }

    func testOrdinaryCommandAndShiftClicksMatchNativeBatchSelection() {
        var selection = LibrarySelectionModel()

        selection.click(ids[2], in: ids)
        XCTAssertEqual(selection.selectedIDs, [ids[2]])
        XCTAssertEqual(selection.activeID, ids[2])

        selection.click(ids[5], in: ids, modifiers: .command)
        XCTAssertEqual(selection.selectedIDs, [ids[2], ids[5]])
        XCTAssertEqual(selection.activeID, ids[5])

        // Shift extends from the last ordinary/Command click and keeps the earlier discontiguous
        // selection, as AppKit list controls do.
        selection.click(ids[7], in: ids, modifiers: .shift)
        XCTAssertEqual(selection.selectedIDs, [ids[2], ids[5], ids[6], ids[7]])
        XCTAssertEqual(selection.activeID, ids[7])
        XCTAssertEqual(selection.anchorID, ids[5])
    }

    func testCommandClickTogglesAndKeepsAValidActivePhoto() {
        var selection = LibrarySelectionModel()
        selection.click(ids[1], in: ids)
        selection.click(ids[4], in: ids, modifiers: .command)
        selection.click(ids[4], in: ids, modifiers: .command)

        XCTAssertEqual(selection.selectedIDs, [ids[1]])
        XCTAssertEqual(selection.activeID, ids[1])

        selection.click(ids[1], in: ids, modifiers: .command)
        XCTAssertTrue(selection.isEmpty)
        XCTAssertNil(selection.activeID)
    }

    func testSelectAllAndRescanReconcileRemovedIDs() {
        var selection = LibrarySelectionModel()
        selection.click(ids[3], in: ids)
        selection.selectAll(in: ids)
        XCTAssertEqual(selection.selectedIDs.count, ids.count)
        XCTAssertEqual(selection.activeID, ids[3])

        selection.reconcile(with: Array(ids.dropFirst(2)))
        XCTAssertEqual(selection.selectedIDs, Set(ids.dropFirst(2)))
        XCTAssertTrue(selection.selectedIDs.contains(selection.activeID!))
        XCTAssertTrue(selection.selectedIDs.contains(selection.anchorID!))
    }

    func testSyntheticThousandItemGridKeepsViewportWorkBounded() {
        let layout = LibraryGridLayout()
        let visible = layout.visibleIndices(
            itemCount: 1_000,
            width: 960,
            viewportHeight: 720,
            scrollOffset: 0
        )

        XCTAssertLessThan(visible.count, 1_000)
        XCTAssertEqual(visible.lowerBound, 0)
        XCTAssertEqual(visible.upperBound, 40, "a viewport should admit only a small prefetch window")

        measure {
            for offset in stride(from: 0.0, through: 120_000.0, by: 600.0) {
                _ = layout.visibleIndices(
                    itemCount: 1_000,
                    width: 960,
                    viewportHeight: 720,
                    scrollOffset: offset
                )
            }
        }
    }
}
