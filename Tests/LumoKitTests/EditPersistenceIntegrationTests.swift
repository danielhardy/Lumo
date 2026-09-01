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
}
