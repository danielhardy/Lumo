import XCTest
@testable import LumoKit

@MainActor
final class LibraryGridTests: TempDirectoryTestCase {
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
