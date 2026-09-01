import XCTest
@testable import LumoKit

/// Comparison presentation is a user preference, not part of a photo's edit document. These tests
/// keep the first-launch, photo-switch, and relaunch contracts together so a new default cannot be
/// accidentally hidden by the existing per-photo persistence tests.
@MainActor
final class ComparisonModeTests: TempDirectoryTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "LumoComparisonModeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeViewModel(defaults: UserDefaults) -> AppViewModel {
        AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(
                fileURL: tempDirectory.appendingPathComponent("edit-records.json")
            ),
            preferences: defaults
        )
    }

    private func waitUntil(
        _ description: String,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() > deadline {
                return XCTFail("timed out waiting for \(description)")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testFirstLaunchDefaultsToSinglePhoto() {
        let viewModel = makeViewModel(defaults: makeDefaults())

        XCTAssertFalse(viewModel.isSideBySide)
        XCTAssertFalse(viewModel.isSideBySideVisible)
    }

    func testSelectedModeIsRememberedAcrossRelaunch() {
        let defaults = makeDefaults()
        let firstLaunch = makeViewModel(defaults: defaults)
        firstLaunch.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }

        XCTAssertTrue(firstLaunch.toggleSideBySide())
        XCTAssertTrue(firstLaunch.isSideBySide)

        let relaunched = makeViewModel(defaults: defaults)
        XCTAssertTrue(relaunched.isSideBySide)
    }

    func testSelectedModeSurvivesPhotoSwitch() async throws {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )

        viewModel.openImage(url: first)
        try await waitUntil("the first photo") { viewModel.sourceName == first.lastPathComponent }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        XCTAssertTrue(viewModel.toggleSideBySide())
        XCTAssertTrue(viewModel.isSideBySideVisible)

        viewModel.openImage(url: second)
        try await waitUntil("the second photo") { viewModel.sourceName == second.lastPathComponent }

        XCTAssertTrue(viewModel.isSideBySide)
        XCTAssertFalse(viewModel.isShowingOriginal, "Space comparison must not leak across photos")
    }

    func testReturningToSinglePhotoModeIsAlsoRemembered() {
        let defaults = makeDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }

        XCTAssertTrue(viewModel.toggleSideBySide())
        XCTAssertTrue(viewModel.toggleSideBySide())
        XCTAssertFalse(viewModel.isSideBySide)

        let relaunched = makeViewModel(defaults: defaults)
        XCTAssertFalse(relaunched.isSideBySide)
    }
}
