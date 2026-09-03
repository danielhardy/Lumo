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

    private func makeViewModel(
        defaults: UserDefaults,
        storeURL: URL? = nil
    ) -> AppViewModel {
        AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(
                fileURL: storeURL ?? tempDirectory.appendingPathComponent("edit-records.json")
            ),
            preferences: defaults
        )
    }

    private func waitUntil(
        _ description: String,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()) {
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
        XCTAssertTrue(viewModel.isSideBySideVisible,
                      "a retained side-by-side preference must remain visible for an identity photo")
        XCTAssertFalse(viewModel.isShowingOriginal, "Space comparison must not leak across photos")
    }

    func testUneditedPhotoPopulatesBothSurfacesWithNoEditRecord() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(
            engine: fake,
            editStore: EditDocumentStore(
                fileURL: tempDirectory.appendingPathComponent("no-record-edits.json")
            ),
            preferences: defaults
        )
        enableSideBySide(on: viewModel)
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "no-record.png", in: tempDirectory
        )

        viewModel.openImage(url: image)
        try await waitForBothSurfaces(viewModel, fake: fake, image: image)

        try await assertIdentityComparison(viewModel, fake: fake, image: image)
    }

    func testUneditedPhotoPopulatesBothSurfacesWithAnEmptyPersistedDocument() async throws {
        let defaults = makeDefaults()
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "empty-record.png", in: tempDirectory
        )
        let storeURL = tempDirectory.appendingPathComponent("empty-record-edits.json")
        let store = EditDocumentStore(fileURL: storeURL)
        try await store.save(
            EditDocument(),
            for: EditSourceReference(assetID: .file(image), url: image)
        )

        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(
            engine: fake,
            editStore: EditDocumentStore(fileURL: storeURL),
            preferences: defaults
        )
        enableSideBySide(on: viewModel)
        viewModel.openImage(url: image)

        try await waitForBothSurfaces(viewModel, fake: fake, image: image)
        try await assertIdentityComparison(viewModel, fake: fake, image: image)
    }

    func testResetPhotoKeepsRetainedSideBySideSurfacesValid() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(
            engine: fake,
            editStore: EditDocumentStore(
                fileURL: tempDirectory.appendingPathComponent("reset-edits.json")
            ),
            preferences: defaults
        )
        enableSideBySide(on: viewModel)
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "reset.png", in: tempDirectory
        )
        viewModel.openImage(url: image)
        try await waitForBothSurfaces(viewModel, fake: fake, image: image)

        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        try await waitUntil("the edited comparison") {
            viewModel.originalPreviewSurface.image != nil
                && viewModel.document.hasVisibleLookEdits
        }
        viewModel.resetPhoto()
        try await waitUntil("the reset comparison") {
            viewModel.document.isIdentity
                && viewModel.isSideBySideVisible
                && viewModel.previewSurface.image != nil
                && viewModel.originalPreviewSurface.image != nil
        }

        XCTAssertTrue(viewModel.isSideBySide)
        XCTAssertTrue(viewModel.toggleSideBySide(), "the retained comparison must be dismissible")
        XCTAssertFalse(viewModel.isSideBySide)
    }

    private func enableSideBySide(on viewModel: AppViewModel) {
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.25)] }
        XCTAssertTrue(viewModel.toggleSideBySide())
    }

    private func waitForBothSurfaces(
        _ viewModel: AppViewModel,
        fake: FakeRenderEngine,
        image: URL
    ) async throws {
        try await waitUntil("the identity comparison surfaces") {
            viewModel.sourceName == image.lastPathComponent
                && viewModel.isSideBySideVisible
                && viewModel.previewSurface.image != nil
                && viewModel.originalPreviewSurface.image != nil
        }
        try await waitUntil("the identity render requests") {
            await fake.previewRequests.count >= 2
        }
    }

    private func assertIdentityComparison(
        _ viewModel: AppViewModel,
        fake: FakeRenderEngine,
        image: URL
    ) async throws {
        XCTAssertTrue(viewModel.document.isIdentity)
        XCTAssertTrue(viewModel.previewSurface.image != nil)
        XCTAssertTrue(viewModel.originalPreviewSurface.image != nil)
        XCTAssertTrue(viewModel.isSideBySide)
        XCTAssertTrue(viewModel.isSideBySideVisible)

        let requests = await fake.previewRequests
        XCTAssertGreaterThanOrEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.document.isIdentity })
        XCTAssertTrue(requests.allSatisfy { $0.source?.backing == .url(image) })
        XCTAssertEqual(viewModel.sourceName, image.lastPathComponent)
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
