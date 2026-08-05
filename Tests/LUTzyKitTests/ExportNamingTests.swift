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
        XCTAssertEqual(ExportFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(ExportFormat.tiff.fileExtension, "tif")
        XCTAssertEqual(ExportFormat.png.fileExtension, "png")

        for format in ExportFormat.allCases {
            XCTAssertTrue(
                format.utType.preferredFilenameExtension == format.fileExtension
                    || format.utType.tags[.filenameExtension]?.contains(format.fileExtension) == true,
                "\(format.rawValue): extension \(format.fileExtension) should belong to \(format.utType.identifier)"
            )
        }
    }

    /// The promotion contract, pinned in Step 7 when `ExportFormat` moved out of `ImageProcessor`.
    ///
    /// `docs/PHASE2_SPEC.md` §7 flagged this move as a risk because everything it depends on fails
    /// *quietly*: a `Picker` whose rows share an `id` still compiles and still draws, it just stops
    /// tracking the selection, and a changed raw value only shows up as a wrong label. Nothing else
    /// in the suite would notice either.
    func testTheToolbarPickerContractSurvivedThePromotion() {
        // The order and labels the toolbar segmented control shows.
        XCTAssertEqual(ExportFormat.allCases.map(\.rawValue), ["TIFF", "JPEG", "PNG"])

        // What the Picker keys its rows by. Duplicates break selection silently.
        let ids = ExportFormat.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ExportFormat.allCases.count, "Picker row ids must be unique")
        XCTAssertEqual(ids, ExportFormat.allCases.map(\.rawValue),
                       "the id is the raw value — changing that changes what a saved selection means")

        // What NSSavePanel filters on.
        XCTAssertEqual(ExportFormat.jpeg.utType, .jpeg)
        XCTAssertEqual(ExportFormat.tiff.utType, .tiff)
        XCTAssertEqual(ExportFormat.png.utType, .png)
    }
}
