import Darwin
import Foundation
import XCTest
@testable import LumoKit

/// Opt-in persistence benchmark. It is excluded from normal test runs because the 10,000-record
/// case intentionally measures whole-catalog JSON replacement. Run with:
/// `LUMO_PERSISTENCE_BENCHMARK=1 swift test --filter EditPersistenceBenchmarkTests`.
@MainActor
final class EditPersistenceBenchmarkTests: TempDirectoryTestCase {

    func testEditedCatalogSizes() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LUMO_PERSISTENCE_BENCHMARK"] == "1")

        for count in [10, 1_000, 10_000] {
            let storeURL = tempDirectory.appendingPathComponent("catalog-\(count).json")
            try seedCatalog(count: count, at: storeURL)
            let imageURL = try Fixtures.writeGradientPNG(
                width: 32, height: 24, named: "benchmark-\(count)-a.png", in: tempDirectory
            )
            let secondImageURL = try Fixtures.writeGradientPNG(
                width: 32, height: 24, named: "benchmark-\(count)-b.png", in: tempDirectory
            )
            let store = EditDocumentStore(fileURL: storeURL)
            let viewModel = AppViewModel(engine: FakeRenderEngine(), editStore: store)
            let cpuBefore = cpuTime()
            let wallBefore = Date()

            viewModel.openImage(url: imageURL)
            try await waitUntil(viewModel: viewModel, description: "benchmark source") {
                viewModel.sourceName == imageURL.lastPathComponent
            }

            for value in stride(from: 0.0, through: 1.0, by: 0.01) {
                viewModel.updateDocument { $0.adjustments = [.exposure(ev: value)] }
            }
            await viewModel.flushPendingWrites()
            let writes = await store.writeCount
            let bytes = await store.bytesWritten
            let peakQueue = viewModel.peakPendingPersistenceCount

            let switchStart = Date()
            viewModel.openImage(url: secondImageURL)
            try await waitUntil(viewModel: viewModel, description: "benchmark source switch") {
                viewModel.sourceName == secondImageURL.lastPathComponent
            }
            let sourceSwitchMilliseconds = Date().timeIntervalSince(switchStart) * 1_000

            viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
            let flushStart = Date()
            await viewModel.flushPendingWrites()
            let terminationFlushMilliseconds = Date().timeIntervalSince(flushStart) * 1_000

            let wallMilliseconds = Date().timeIntervalSince(wallBefore) * 1_000
            let cpuMilliseconds = (cpuTime() - cpuBefore) * 1_000
            let cpuText = String(format: "%.2f", cpuMilliseconds)
            let wallText = String(format: "%.2f", wallMilliseconds)
            let switchText = String(format: "%.2f", sourceSwitchMilliseconds)
            let flushText = String(format: "%.2f", terminationFlushMilliseconds)
            print("PERSISTENCE_BENCHMARK {\"catalog\":\(count),\"writes\":\(writes),\"bytes\":\(bytes),\"peakQueue\":\(peakQueue),\"cpuMs\":\(cpuText),\"wallMs\":\(wallText),\"sourceSwitchMs\":\(switchText),\"terminationFlushMs\":\(flushText)}")
        }
    }

    private func waitUntil(
        viewModel: AppViewModel,
        description: String,
        timeout: TimeInterval = 10,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func seedCatalog(count: Int, at url: URL) throws {
        let document = EditDocument(adjustments: [.exposure(ev: 0.25)])
        let documentObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(document)
        )
        var records: [String: Any] = [:]
        for index in 0..<count {
            let sourceURL = tempDirectory.appendingPathComponent("catalog-photo-\(index).jpg")
            records[PhotoAssetID.file(sourceURL).description] = [
                "document": documentObject,
                "source": [
                    "path": sourceURL.path,
                    "fileName": sourceURL.lastPathComponent,
                    "bookmarkData": NSNull()
                ]
            ]
        }
        let envelope: [String: Any] = ["schemaVersion": 1, "records": records]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func cpuTime() -> TimeInterval {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
            + TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
    }
}
