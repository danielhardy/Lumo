import XCTest
@testable import LumoKit

@MainActor
final class PhotosDeliveryTests: TempDirectoryTestCase {

    @MainActor
    private final class FakePhotosDelivery: PhotosDelivering {
        struct Call: Equatable {
            let data: Data
            let filename: String
            let format: ExportFormat
            let options: PhotosExportOptions
        }

        var calls: [Call] = []
        var result = PhotosDeliveryResult(assetAdded: true)
        var error: Error?

        func deliver(
            data: Data,
            filename: String,
            format: ExportFormat,
            options: PhotosExportOptions
        ) async throws -> PhotosDeliveryResult {
            calls.append(Call(data: data, filename: filename, format: format, options: options))
            if let error { throw error }
            return result
        }
    }

    private func source() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 16, named: "source.png", in: tempDirectory
        )
        return ImageSource(url: url, nativeExtent: CGSize(width: 16, height: 16))
    }

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for (description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testPhotosOptionsTrimAlbumNamesAndRoundTrip() throws {
        let options = PhotosExportOptions(albumName: "  Lumo Exports  ")
        XCTAssertEqual(options.albumName, "Lumo Exports")
        XCTAssertNil(PhotosExportOptions(albumName: " \n\t ").albumName)

        let encoded = try JSONEncoder().encode(options)
        XCTAssertEqual(try JSONDecoder().decode(PhotosExportOptions.self, from: encoded), options)
        XCTAssertEqual(PhotosAuthorizationState.denied.recoveryMessage?.contains("System Settings"), true)
        XCTAssertEqual(PhotosAuthorizationState.limited.recoveryMessage?.contains("limited"), true)
    }

    func testSinglePhotosFailureLeavesCommittedFileAndReportsSeparateFailure() async throws {
        let photos = FakePhotosDelivery()
        photos.error = PhotosDeliveryError.authorization(.denied)
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        var statuses: [String] = []
        var errors: [String] = []
        coordinator.onStatus = { statuses.append($0) }
        coordinator.onError = { errors.append($0) }
        let destination = tempDirectory.appendingPathComponent("safe.jpg")

        coordinator.performExport(
            source: try source(),
            document: EditDocument(),
            lut: nil,
            options: ExportOptions(
                format: .jpeg,
                destination: .file(destination),
                photos: PhotosExportOptions(albumName: "Lumo")
            ),
            to: destination
        )
        try await waitUntil("the export") { !coordinator.isExporting }

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(photos.calls.count, 1)
        XCTAssertTrue(statuses.contains("Exported: safe.jpg"))
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("Photos delivery failed"), errors[0])
        XCTAssertTrue(errors[0].contains("file is safe"), errors[0])
        XCTAssertFalse(errors[0].hasPrefix("Export failed:"), errors[0])
    }

    func testSinglePhotosDeliveryReceivesTheCompletedEncodedDataAndAlbum() async throws {
        let photos = FakePhotosDelivery()
        photos.result = PhotosDeliveryResult(assetAdded: true, albumAdded: true)
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        coordinator.onError = { XCTFail("unexpected error: \($0)") }
        let destination = tempDirectory.appendingPathComponent("graded.jpg")

        coordinator.performExport(
            source: try source(), document: EditDocument(), lut: nil,
            options: ExportOptions(
                format: .jpeg,
                destination: .file(destination),
                photos: PhotosExportOptions(albumName: "Lumo Exports")
            ),
            to: destination
        )
        try await waitUntil("the export") { !coordinator.isExporting }

        XCTAssertEqual(photos.calls.count, 1)
        let call = try XCTUnwrap(photos.calls.first)
        XCTAssertEqual(call.data, try Data(contentsOf: destination))
        XCTAssertEqual(call.filename, "graded.jpg")
        XCTAssertEqual(call.format, .jpeg)
        XCTAssertEqual(call.options.albumName, "Lumo Exports")
    }

    func testBatchPhotosFailuresAreCountedSeparatelyFromRenderFailures() async throws {
        let photos = FakePhotosDelivery()
        photos.error = PhotosDeliveryError.authorization(.restricted)
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        coordinator.onError = { XCTFail("unexpected render error: \($0)") }
        let folder = tempDirectory.appendingPathComponent("batch")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 16, named: "batch-source.png", in: tempDirectory
        )

        let outcome = await coordinator.performBatchExport(
            [ExportCoordinator.BatchItem(url: url, data: nil, name: "batch-source")],
            document: EditDocument(),
            lut: nil,
            options: ExportOptions(
                format: .png,
                destination: .folder(folder),
                photos: PhotosExportOptions()
            ),
            to: folder
        )

        XCTAssertEqual(outcome, .init(exported: 1, failed: 0, total: 1, photosFailed: 1))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("batch-source.png").path
        ))
        XCTAssertTrue(ExportCoordinator.summary(for: outcome, folder: folder).contains("Photos: 1 failed"))
    }
}
