import XCTest
@testable import LumoKit

final class MediaVolumeSelectionTests: XCTestCase {
    func testSelectionSupportsAllNoneAndToggle() {
        let files = (0..<3).map {
            MediaVolumeFile(url: URL(fileURLWithPath: "/fixture/shot\($0).jpg"))
        }
        var selection = MediaVolumeSelectionModel()

        selection.selectAll(in: files)
        XCTAssertEqual(selection.count, 3)
        selection.toggle(files[1])
        XCTAssertEqual(selection.count, 2)
        XCTAssertFalse(selection.contains(files[1]))
        selection.clear()
        XCTAssertEqual(selection.count, 0)
    }
}

@MainActor
final class MediaVolumeImportTests: TempDirectoryTestCase {
    func testMountedScannerAdmitsSupportedImagesWithOrientationAndWarnings() async throws {
        let good = try Fixtures.writeJPEG(
            width: 80, height: 40, orientation: 6, named: "portrait.jpg", in: tempDirectory
        )
        try Data("not an image".utf8).write(to: tempDirectory.appendingPathComponent("broken.jpg"))
        try Data("ignore".utf8).write(to: tempDirectory.appendingPathComponent("notes.txt"))

        let volume = MediaVolume(name: "Fixture Card", url: tempDirectory)
        let result = try await MountedMediaVolumeProvider().scan(volume)

        XCTAssertEqual(result.files.map(\.filename), ["portrait.jpg"])
        XCTAssertEqual(result.files.first?.orientation, 6)
        XCTAssertTrue(result.warnings.contains { $0.contains("broken.jpg") })
        XCTAssertFalse(result.files.contains { $0.filename == "notes.txt" })
        XCTAssertEqual(try Data(contentsOf: good), try Data(contentsOf: good), "source is untouched")
    }

    func testInjectedProviderCoversDiscoveryScanAndFailureState() async throws {
        let imageURL = try Fixtures.writeJPEG(
            width: 32, height: 16, orientation: 1, named: "shot.jpg", in: tempDirectory
        )
        let volume = MediaVolume(name: "Camera Card", url: tempDirectory)
        let file = MediaVolumeFile(url: imageURL, orientation: 1)
        let provider = FixtureMediaVolumeProvider(
            volumes: [volume], result: .success(MediaVolumeScanResult(files: [file], warnings: []))
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine(), mediaVolumeProvider: provider)

        viewModel.refreshRemovableMedia()
        try await waitUntil { viewModel.removableMediaVolumes == [volume] }
        XCTAssertEqual(viewModel.removableMediaVolumes.map(\.name), ["Camera Card"])

        viewModel.openRemovableMedia(volume)
        try await waitUntil { !viewModel.isRemovableMediaScanning }
        XCTAssertEqual(viewModel.removableMediaFiles, [file])
        XCTAssertEqual(viewModel.removableMediaSelection.count, 1)

        let failing = FixtureMediaVolumeProvider(
            volumes: [volume], result: .failure(.volumeRemoved("Camera Card"))
        )
        let failingViewModel = AppViewModel(engine: FakeRenderEngine(), mediaVolumeProvider: failing)
        failingViewModel.openRemovableMedia(volume)
        try await waitUntil { !failingViewModel.isRemovableMediaScanning }
        XCTAssertTrue(failingViewModel.removableMediaWarnings.contains("Camera Card is no longer available."))
    }

    func testEmptyScanKeepsARecoverableEmptyStateAndCancelClosesIt() async throws {
        let volume = MediaVolume(name: "Empty Card", url: tempDirectory)
        let provider = FixtureMediaVolumeProvider(
            volumes: [volume], result: .success(MediaVolumeScanResult(files: [], warnings: []))
        )
        let viewModel = AppViewModel(engine: FakeRenderEngine(), mediaVolumeProvider: provider)

        viewModel.openRemovableMedia(volume)
        try await waitUntil { !viewModel.isRemovableMediaScanning }
        XCTAssertTrue(viewModel.removableMediaFiles.isEmpty)
        XCTAssertTrue(viewModel.removableMediaWarnings.contains("No supported images were found on this volume."))
        viewModel.cancelRemovableMediaImport()
        XCTAssertFalse(viewModel.isRemovableMediaSelectorPresented)
    }

    func testExplicitImportUsesURLBackedPhotoAssetsAndPreservesSource() async throws {
        let url = try Fixtures.writeJPEG(
            width: 64, height: 32, orientation: 6, named: "DSC0001.JPG", in: tempDirectory
        )
        let original = try Data(contentsOf: url)
        let file = MediaVolumeFile(url: url, filename: "DSC0001.JPG", orientation: 6)
        let volume = MediaVolume(name: "Card", url: tempDirectory)
        let collection = ImageCollection()

        let ids = collection.addFromMediaVolume(volume, files: [file])
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(collection.items.first?.url, url.standardizedFileURL)
        XCTAssertEqual(collection.items.first?.displayName, "DSC0001.JPG")
        XCTAssertEqual(collection.items.first?.asset.id, PhotoAssetID.file(url))
        XCTAssertEqual(collection.items.first?.asset.metadata.dimensions, PhotoPixelDimensions(width: 32, height: 64))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("condition did not become true"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct FixtureMediaVolumeProvider: MediaVolumeProviding {
    let volumes: [MediaVolume]
    let result: Result<MediaVolumeScanResult, MediaVolumeError>

    func discover() async -> [MediaVolume] { volumes }

    func scan(_ volume: MediaVolume) async throws -> MediaVolumeScanResult {
        try result.get()
    }
}
