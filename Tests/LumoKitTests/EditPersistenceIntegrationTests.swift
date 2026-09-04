import Foundation
import XCTest
@testable import LumoKit

@MainActor
final class EditPersistenceIntegrationTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                return XCTFail("timed out waiting for \(description)")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitUntilStoreReady(
        _ store: EditDocumentStore,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await store.status != .ready {
            if Date() > deadline {
                return XCTFail("timed out waiting for the edit store")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testEditedPhotoSurvivesAViewModelRelaunch() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "relaunch.png", in: tempDirectory
        )
        let storeURL = tempDirectory.appendingPathComponent("edit-records.json")

        let firstLaunch = AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(fileURL: storeURL)
        )
        firstLaunch.openImage(url: imageURL)
        try await waitUntil("the first image") {
            firstLaunch.sourceName == imageURL.lastPathComponent
        }
        firstLaunch.updateDocument { $0.adjustments = [.exposure(ev: 0.8)] }
        try await waitUntilStoreReady(firstLaunch.editStore)

        let secondLaunch = AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(fileURL: storeURL)
        )
        secondLaunch.openImage(url: imageURL)
        try await waitUntil("the restored image") {
            secondLaunch.sourceName == imageURL.lastPathComponent
                && secondLaunch.document.adjustments == [.exposure(ev: 0.8)]
        }
    }

    func testImmediateEditCanBeFlushedBeforeRelaunch() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "immediate.png", in: tempDirectory
        )
        let storeURL = tempDirectory.appendingPathComponent("immediate-edits.json")
        let firstLaunch = AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(fileURL: storeURL)
        )
        firstLaunch.openImage(url: imageURL)
        try await waitUntil("the first image") { firstLaunch.sourceImage != nil }
        firstLaunch.updateDocument {
            $0.lut = LUTSettings(lutID: LUTID(raw: "look.cube"), intensity: 0.42)
        }

        // This intentionally does not wait for editStore.status. Clean termination must provide
        // the ordering guarantee even when the edit is made immediately before Cmd-Q.
        await firstLaunch.flushPendingWrites()

        let secondLaunch = AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(fileURL: storeURL)
        )
        secondLaunch.openImage(url: imageURL)
        try await waitUntil("the flushed Look") {
            secondLaunch.sourceName == imageURL.lastPathComponent
                && secondLaunch.document.lut.intensity == 0.42
                && secondLaunch.document.lut.lutID?.raw == "look.cube"
        }
    }

    func testRapidEditsCoalesceToOneLatestSnapshotPerAsset() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "coalesced.png", in: tempDirectory
        )
        let store = EditDocumentStore(
            fileURL: tempDirectory.appendingPathComponent("coalesced-edits.json")
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine(), editStore: store)
        viewModel.openImage(url: imageURL)
        try await waitUntil("the coalesced image") { viewModel.sourceImage != nil }

        for value in stride(from: 0.0, through: 1.0, by: 0.05) {
            viewModel.updateDocument { $0.adjustments = [.exposure(ev: value)] }
        }

        XCTAssertLessThanOrEqual(viewModel.pendingPersistenceCount, 1)
        await viewModel.flushPendingWrites()

        let restored = EditDocumentStore(
            fileURL: tempDirectory.appendingPathComponent("coalesced-edits.json")
        )
        let result = await restored.load(
            for: EditSourceReference(assetID: .file(imageURL), url: imageURL)
        )
        XCTAssertEqual(result.document.adjustments, [.exposure(ev: 1.0)])
        let writeCount = await store.writeCount
        XCTAssertEqual(writeCount, 1)
    }

    func testForcedFlushWaitsForAnInFlightSlowWrite() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "slow-flush.png", in: tempDirectory
        )
        let store = EditDocumentStore(
            fileURL: tempDirectory.appendingPathComponent("slow-flush-edits.json"),
            artificialWriteDelay: .milliseconds(400)
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine(), editStore: store)
        viewModel.openImage(url: imageURL)
        try await waitUntil("the slow-flush image") { viewModel.sourceImage != nil }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.6)] }
        // The normal worker waits 250 ms before its first checkpoint. Yield just after that
        // checkpoint so the forced flush has to chain behind the deliberately slow write.
        try await Task.sleep(for: .milliseconds(270))

        let started = Date()
        await viewModel.flushPendingWrites()
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertGreaterThanOrEqual(elapsed, 0.25)
        XCTAssertEqual(viewModel.pendingPersistenceCount, 0)
        let writeCount = await store.writeCount
        XCTAssertEqual(writeCount, 1)
        let restored = EditDocumentStore(fileURL: tempDirectory.appendingPathComponent("slow-flush-edits.json"))
        let result = await restored.load(for: EditSourceReference(assetID: .file(imageURL), url: imageURL))
        XCTAssertEqual(result.document.adjustments, [.exposure(ev: 0.6)])
    }

    func testFailedPersistenceRemainsDirtyUntilAForcedRetrySucceeds() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "retry.png", in: tempDirectory
        )
        let store = EditDocumentStore(
            fileURL: tempDirectory.appendingPathComponent("retry-edits.json"),
            failuresBeforeSuccess: 1
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine(), editStore: store)
        viewModel.openImage(url: imageURL)
        try await waitUntil("the retry image") { viewModel.sourceImage != nil }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.7)] }
        await viewModel.flushPendingWrites()
        XCTAssertEqual(viewModel.pendingPersistenceCount, 1)
        let failedWriteCount = await store.writeCount
        XCTAssertEqual(failedWriteCount, 0)

        await viewModel.flushPendingWrites()
        XCTAssertEqual(viewModel.pendingPersistenceCount, 0)
        let writeCount = await store.writeCount
        XCTAssertEqual(writeCount, 1)
    }

    func testFailedTerminationFlushCannotApproveQuitSilently() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "failed-termination.png", in: tempDirectory
        )
        let store = EditDocumentStore(
            fileURL: tempDirectory.appendingPathComponent("failed-termination-edits.json"),
            failuresBeforeSuccess: 1
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine(), editStore: store)
        viewModel.openImage(url: imageURL)
        try await waitUntil("the failed-termination image") { viewModel.sourceImage != nil }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.8)] }

        let result = await viewModel.flushPendingWrites()

        guard case .failure = result else {
            return XCTFail("a failed termination flush must report failure")
        }
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(viewModel.pendingPersistenceCount, 1,
                       "failed edits must remain dirty instead of being approved as saved")

        let retry = await viewModel.flushPendingWrites()
        XCTAssertTrue(retry.succeeded)
        XCTAssertEqual(viewModel.pendingPersistenceCount, 0)
    }

    func testCancelledFlushIsReportedDistinctly() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "cancelled-flush.png", in: tempDirectory
        )
        let store = EditDocumentStore(
            fileURL: tempDirectory.appendingPathComponent("cancelled-flush-edits.json"),
            artificialWriteDelay: .milliseconds(250)
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine(), editStore: store)
        viewModel.openImage(url: imageURL)
        try await waitUntil("the cancelled-flush image") { viewModel.sourceImage != nil }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.2)] }

        let flush = Task { @MainActor in await viewModel.flushPendingWrites() }
        try await Task.sleep(for: .milliseconds(20))
        flush.cancel()
        let result = await flush.value

        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(viewModel.pendingPersistenceCount <= 1)
    }

    func testRacedFlushReportsSuccessAfterReplacementDrainsQueue() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "raced-flush.png", in: tempDirectory
        )
        let store = EditDocumentStore(
            fileURL: tempDirectory.appendingPathComponent("raced-flush-edits.json"),
            artificialWriteDelay: .milliseconds(100)
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine(), editStore: store)
        viewModel.openImage(url: imageURL)
        try await waitUntil("the raced-flush image") { viewModel.sourceImage != nil }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.4)] }

        let firstFlush = Task { @MainActor in await viewModel.flushPendingWrites() }
        // The injected delay happens after the atomic write, while the store.save call is still
        // suspended. Avoid polling the actor here: its blocking test delay would prevent the
        // polling accessor from observing the in-flight operation at all.
        try await Task.sleep(for: .milliseconds(20))

        // The first flush is awaiting an in-flight write. The second flush cancels and replaces
        // that worker. The first worker has already made the snapshot durable, so its cancellation
        // result arrives with an empty queue; flush must map that result to success.
        let replacementFlush = Task { @MainActor in await viewModel.flushPendingWrites() }
        let replacementResult = await replacementFlush.value
        let firstResult = await firstFlush.value

        XCTAssertTrue(replacementResult.succeeded)
        XCTAssertEqual(firstResult, .success)
        XCTAssertEqual(viewModel.pendingPersistenceCount, 0)
        let writeCount = await store.writeCount
        XCTAssertEqual(writeCount, 1)
    }

    func testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "long-gesture.png", in: tempDirectory
        )
        let store = EditDocumentStore(
            fileURL: tempDirectory.appendingPathComponent("long-gesture-edits.json")
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine(), editStore: store)
        viewModel.openImage(url: imageURL)
        try await waitUntil("the long-gesture image") { viewModel.sourceImage != nil }

        viewModel.beginUndoGrouping()
        for value in [0.1, 0.2, 0.3] {
            viewModel.updateDocument { $0.adjustments = [.exposure(ev: value)] }
            try await Task.sleep(for: .milliseconds(300))
        }

        let intermediateWriteCount = await store.writeCount
        XCTAssertGreaterThan(intermediateWriteCount, 1)
        viewModel.endUndoGrouping()
        await viewModel.flushPendingWrites()
        XCTAssertEqual(viewModel.pendingPersistenceCount, 0)
        let finalWriteCount = await store.writeCount
        XCTAssertGreaterThanOrEqual(finalWriteCount, 2)
    }

    func testMissingSourceStillReportsAnActionableLoadError() async throws {
        let viewModel = AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(
                fileURL: tempDirectory.appendingPathComponent("edit-records.json")
            )
        )
        let missing = tempDirectory.appendingPathComponent("gone.png")
        viewModel.openImage(url: missing)

        try await waitUntil("the missing-source error") {
            viewModel.errorMessage != nil
        }
        XCTAssertTrue(viewModel.errorMessage?.contains("gone.png") == true)
    }

    func testLateEditStoreResultCannotOverwriteAnInMemoryEdit() async throws {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "late-store.png", in: tempDirectory
        )
        let store = EditDocumentStore(
            fileURL: tempDirectory.appendingPathComponent("late-store-edits.json")
        )
        try await store.save(
            EditDocument(adjustments: [.exposure(ev: 0.1)]),
            for: EditSourceReference(assetID: .file(imageURL), url: imageURL)
        )
        let engine = FakeRenderEngine()
        await engine.gateSourcePreparation()
        let viewModel = AppViewModel(engine: engine, editStore: store)

        viewModel.openImage(url: imageURL)
        while await engine.sourcePreparationCount < 1 { await Task.yield() }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.9)] }
        await engine.releaseSourcePreparation()

        try await waitUntil("the prepared source") { viewModel.sourceImage != nil }
        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.9)])
    }
}
