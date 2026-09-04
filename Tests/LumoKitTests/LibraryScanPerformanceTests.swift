import XCTest

@testable import LumoKit

/// Opt-in folder-scan timing harness for the sizes that expose identity and publication scaling
/// problems. It uses valid, repeated JPEG bytes so the metadata stage follows the same path as a
/// real photo folder without checking a large fixture into the repository.
@MainActor
final class LibraryScanPerformanceTests: TempDirectoryTestCase {

    func testProfileFolderScanAt1KAnd10KItems() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_SCAN_BENCHMARK"] != nil,
            "set LUMO_SCAN_BENCHMARK=1 to run the 1k/10k folder scan timing harness"
        )

        let sampleURL = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "sample.jpg", in: tempDirectory
        )
        let sample = try Data(contentsOf: sampleURL)
        try FileManager.default.removeItem(at: sampleURL)

        for count in [1_000, 10_000] {
            let folder = tempDirectory.appendingPathComponent("folder-\(count)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<count {
                let group = folder.appendingPathComponent(String(format: "group-%02d", index % 10))
                try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
                try sample.write(to: group.appendingPathComponent(
                    String(format: "photo-%05d.jpg", index)
                ))
            }

            let collection = ImageCollection()
            let start = DispatchTime.now().uptimeNanoseconds
            collection.loadFromFolder(folder)
            let firstRowStart = DispatchTime.now().uptimeNanoseconds
            while collection.items.isEmpty {
                await Task.yield()
            }
            let firstRowEnd = DispatchTime.now().uptimeNanoseconds
            while collection.isScanning {
                await Task.yield()
            }
            let end = DispatchTime.now().uptimeNanoseconds

            XCTAssertEqual(collection.items.count, count)
            let expectedNames = (0..<count).map { index in
                (
                    group: String(format: "group-%02d", index % 10),
                    name: String(format: "photo-%05d", index)
                )
            }.sorted {
                let groupOrder = $0.group.localizedStandardCompare($1.group)
                if groupOrder != .orderedSame { return groupOrder == .orderedAscending }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }.map(\.name)
            XCTAssertEqual(collection.items.map(\.displayName), expectedNames)
            print(String(format: "LIBRARY_SCAN_PROFILE items=%d first_row_ms=%.1f discovery_ms=%.1f",
                         count,
                         Double(firstRowEnd - firstRowStart) / 1_000_000,
                         Double(end - start) / 1_000_000))
            // The benchmark isolates folder discovery/identity publication. Deferred ImageIO
            // metadata is deliberately not part of this timing and is cancelled before the next
            // 10k-item fixture is created.
            collection.clear()
        }
    }
}
