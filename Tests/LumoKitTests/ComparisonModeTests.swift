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

    func testEnteringSideBySideAfterSettledPreviewRequestsAndPublishesBaseline() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(
            engine: fake,
            editStore: EditDocumentStore(
                fileURL: tempDirectory.appendingPathComponent("settled-entry-edits.json")
            ),
            preferences: defaults
        )
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "settled-entry.png", in: tempDirectory
        )

        viewModel.openImage(url: image)
        try await waitUntil("the settled adjusted preview") {
            viewModel.sourceName == image.lastPathComponent
                && viewModel.previewSurface.image != nil
        }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        let expectedDocument = viewModel.document
        try await waitUntil("the settled edited preview") {
            guard viewModel.document == expectedDocument else { return false }
            let requests = await fake.previewRequests
            return requests.contains { $0.document == expectedDocument }
        }

        let requestCountBeforeToggle = await fake.previewRequests.count
        XCTAssertTrue(viewModel.toggleSideBySide())

        try await waitUntil("the baseline preview") {
            viewModel.isSideBySideVisible
                && viewModel.originalPreviewSurface.image != nil
        }
        let requests = await fake.previewRequests
        XCTAssertGreaterThan(requests.count, requestCountBeforeToggle)
        XCTAssertTrue(requests.contains {
            $0.document == viewModel.document.comparisonBaseline
                && $0.lutID == nil
                && $0.source?.backing == .url(image)
        })
        XCTAssertNotNil(viewModel.previewSurface.image)
        XCTAssertNotNil(viewModel.originalPreviewSurface.image)
    }

    func testEntryDoesNotWaitForDrawableConfirmationBeforeRequestingBaseline() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(
            engine: fake,
            editStore: EditDocumentStore(
                fileURL: tempDirectory.appendingPathComponent("drawable-entry-edits.json")
            ),
            preferences: defaults
        )
        // The real MTKView owns this lifecycle. Modeling it here keeps the regression test focused
        // on the gap between a settled publication and its later drawable confirmation.
        viewModel.previewSurface.attachPresentationLifecycle()
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "drawable-entry.png", in: tempDirectory
        )

        viewModel.openImage(url: image)
        try await waitUntil("the initial preview publication") {
            viewModel.sourceName == image.lastPathComponent
                && viewModel.previewSurface.image != nil
        }
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        let expectedDocument = viewModel.document
        try await waitUntil("the settled edited publication") {
            guard viewModel.document == expectedDocument else { return false }
            let requests = await fake.previewRequests
            return requests.contains { $0.document == expectedDocument }
        }

        XCTAssertTrue(viewModel.toggleSideBySide())
        try await waitUntil("the baseline without drawable confirmation") {
            viewModel.isSideBySideVisible
                && viewModel.originalPreviewSurface.image != nil
        }
        let requests = await fake.previewRequests
        XCTAssertTrue(requests.contains {
            $0.document == viewModel.document.comparisonBaseline && $0.lutID == nil
        })
    }

    func testLateBaselineFromPreviousPhotoCannotPublish() async throws {
        let defaults = makeDefaults()
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(
            engine: fake,
            editStore: EditDocumentStore(
                fileURL: tempDirectory.appendingPathComponent("late-baseline-edits.json")
            ),
            preferences: defaults
        )
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "late-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "late-second.png", in: tempDirectory
        )

        viewModel.openImage(url: first)
        try await waitUntil("the first main preview request") { await fake.previewRequests.count >= 1 }
        try await waitUntil("the first main preview") { viewModel.previewSurface.image != nil }

        await fake.gatePreviews()
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        try await waitUntil("the edited first preview request") {
            let requests = await fake.previewRequests
            return requests.contains {
                $0.source?.backing == .url(first) && $0.document == viewModel.document
            }
        }
        XCTAssertTrue(viewModel.toggleSideBySide())
        await fake.releaseNextPreview()
        try await waitUntil("the first baseline request") { await fake.previewRequests.count == 3 }

        viewModel.openImage(url: second)
        XCTAssertNil(viewModel.originalPreviewSurface.image,
                     "the source switch must clear the previous baseline immediately")
        try await waitUntil("the second source") { viewModel.sourceName == second.lastPathComponent }
        await fake.releaseNextPreview()
        try await waitUntil("the second main preview request") { await fake.previewRequests.count >= 4 }
        XCTAssertNil(viewModel.originalPreviewSurface.image,
                     "a late baseline from the previous source must not repopulate the pane")
        await fake.releasePreviews()

        try await waitUntil("the second comparison") {
            viewModel.isSideBySideVisible
                && viewModel.previewSurface.image != nil
                && viewModel.originalPreviewSurface.image != nil
        }
        let requests = await fake.previewRequests
        XCTAssertTrue(requests.contains { $0.source?.backing == .url(first) && $0.document == EditDocument() })
        XCTAssertTrue(requests.contains { $0.source?.backing == .url(second) && $0.document == EditDocument() })
        XCTAssertTrue(requests.filter { $0.source?.backing == .url(second) }.allSatisfy {
            $0.document == EditDocument()
        })
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
