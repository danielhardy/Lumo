import XCTest
@testable import LumoKit

@MainActor
final class LibraryGridTests: TempDirectoryTestCase {
    func testMosaicRowsPreserveMixedOrientationWithoutOverlapAtRepresentativeWidths() {
        let layout = LibraryGridLayout()
        let aspects = [1.5, 0.75, 1.0, 1.5, 0.75, 1.0, 1.5, 0.75]

        for width in [320.0, 768.0, 1_280.0] {
            let rows = layout.mosaicRows(aspectRatios: aspects, width: width)
            XCTAssertEqual(rows.flatMap(\.itemIndices), Array(aspects.indices))

            for row in rows {
                XCTAssertEqual(row.itemIndices.count, row.itemWidths.count)
                XCTAssertGreaterThan(row.imageHeight, 0)
                XCTAssertLessThanOrEqual(
                    row.itemWidths.reduce(0, +) + layout.spacing * Double(max(0, row.itemWidths.count - 1)),
                    max(width, layout.minimumCellWidth) + 0.001
                )
                XCTAssertTrue(row.itemWidths.allSatisfy { $0 > 0 })
            }
        }
    }

    func testMosaicRowsKeepCellIdentityAndAspectRatioAttachedToSourceOrder() {
        let layout = LibraryGridLayout()
        let aspects = [3.0 / 2.0, 3.0 / 4.0, 1.0]
        let rows = layout.mosaicRows(aspectRatios: aspects, width: 900)
        let positions = rows.flatMap { row in
            zip(row.itemIndices, row.itemWidths).map { ($0, $1 / row.imageHeight) }
        }

        XCTAssertEqual(positions.map(\.0), [0, 1, 2])
        for (index, ratio) in positions {
            XCTAssertEqual(ratio, aspects[index], accuracy: 0.000_001)
        }
    }

    func testInvalidAspectRatiosUseStablePhotographicFallback() {
        XCTAssertEqual(LibraryGridLayout.normalizedAspectRatio(.nan), 4.0 / 3.0)
        XCTAssertEqual(LibraryGridLayout.normalizedAspectRatio(.infinity), 4.0 / 3.0)
        XCTAssertEqual(LibraryGridLayout.normalizedAspectRatio(0), 4.0 / 3.0)
        XCTAssertEqual(LibraryGridLayout.normalizedAspectRatio(10), 3.0)
    }

    func testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding() async throws {
        for index in 0..<64 {
            try Fixtures.writeJPEG(
                width: 64,
                height: 48,
                orientation: 1,
                named: String(format: "photo-%03d.jpg", index),
                in: tempDirectory
            )
        }

        let scheduler = ImageWorkScheduler(configuration: .init(
            maxConcurrentThumbnails: 1,
            maxQueuedThumbnails: 4
        ))
        let collection = ImageCollection(scheduler: scheduler)
        collection.beginThumbnailDemand()
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()

        XCTAssertEqual(collection.items.count, 64)
        XCTAssertTrue(
            collection.items.allSatisfy { $0.thumbnail == nil },
            "a virtualized grid must not decode every discovered cell before it appears"
        )

        let firstID = try XCTUnwrap(collection.items.first?.id)
        collection.requestThumbnail(for: firstID)

        let deadline = Date().addingTimeInterval(5)
        while collection.items.first?.thumbnail == nil {
            if Date() > deadline { return XCTFail("the materialized cell thumbnail did not arrive") }
            await Task.yield()
        }

        XCTAssertTrue(
            collection.items.dropFirst().allSatisfy { $0.thumbnail == nil },
            "requesting one materialized cell must not admit the rest of the folder"
        )
    }
}
