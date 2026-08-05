import XCTest
@testable import LUTzyKit

/// Batch export writes every image into one folder, so two source files with
/// the same basename in different subfolders collide. `uniqueExportURL` is what
/// keeps the second one from silently overwriting the first.
final class ExportNamingTests: TempDirectoryTestCase {

    func testReturnsPlainNameWhenNothingCollides() {
        let url = uniqueExportURL(in: tempDirectory, base: "photo", ext: "jpg")
        XCTAssertEqual(url.lastPathComponent, "photo.jpg")
    }

    func testAppendsCounterOnCollision() throws {
        try Data().write(to: tempDirectory.appendingPathComponent("photo.jpg"))
        XCTAssertEqual(
            uniqueExportURL(in: tempDirectory, base: "photo", ext: "jpg").lastPathComponent,
            "photo 2.jpg"
        )

        try Data().write(to: tempDirectory.appendingPathComponent("photo 2.jpg"))
        XCTAssertEqual(
            uniqueExportURL(in: tempDirectory, base: "photo", ext: "jpg").lastPathComponent,
            "photo 3.jpg"
        )
    }

    func testCollisionsAreScopedToTheExtension() throws {
        try Data().write(to: tempDirectory.appendingPathComponent("photo.jpg"))
        XCTAssertEqual(
            uniqueExportURL(in: tempDirectory, base: "photo", ext: "png").lastPathComponent,
            "photo.png",
            "a .jpg on disk should not push the .png export to a counter"
        )
    }

    func testHandlesNamesWithSpacesAndDots() {
        let url = uniqueExportURL(in: tempDirectory, base: "my photo v1.2", ext: "tif")
        XCTAssertEqual(url.lastPathComponent, "my photo v1.2.tif")
    }

    /// The names batch export actually generates: source name + LUT suffix.
    func testMatchesTheBatchExportNamingScheme() throws {
        let base = "R0010966" + "_" + "Ricoh_GR2_Posi"
        let first = uniqueExportURL(in: tempDirectory, base: base, ext: "jpg")
        XCTAssertEqual(first.lastPathComponent, "R0010966_Ricoh_GR2_Posi.jpg")

        try Data().write(to: first)
        let second = uniqueExportURL(in: tempDirectory, base: base, ext: "jpg")
        XCTAssertEqual(second.lastPathComponent, "R0010966_Ricoh_GR2_Posi 2.jpg")
        XCTAssertNotEqual(first, second, "two same-named sources must not overwrite each other")
    }

    // MARK: - Export format mapping

    func testExportFormatExtensionsAndTypesAgree() {
        XCTAssertEqual(ImageProcessor.ExportFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(ImageProcessor.ExportFormat.tiff.fileExtension, "tif")
        XCTAssertEqual(ImageProcessor.ExportFormat.png.fileExtension, "png")

        for format in ImageProcessor.ExportFormat.allCases {
            XCTAssertTrue(
                format.utType.preferredFilenameExtension == format.fileExtension
                    || format.utType.tags[.filenameExtension]?.contains(format.fileExtension) == true,
                "\(format.rawValue): extension \(format.fileExtension) should belong to \(format.utType.identifier)"
            )
        }
    }
}
