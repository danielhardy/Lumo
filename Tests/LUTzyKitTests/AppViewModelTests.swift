import XCTest
import CoreImage
import simd
@testable import LUTzyKit

/// The coordinators report *what* happened; `AppViewModel` decides how it's
/// shown. That wiring is a set of closures assigned in `init`, and a closure
/// left unassigned fails silently — the status bar simply stops updating and
/// errors never reach the alert. These tests pin it down.
@MainActor
final class AppViewModelTests: TempDirectoryTestCase {

    func testExportStatusReachesTheStatusBar() {
        let viewModel = AppViewModel()
        viewModel.export.onStatus?("Exported: photo.jpg")
        XCTAssertEqual(viewModel.statusMessage, "Exported: photo.jpg")
    }

    func testExportErrorReachesBothTheAlertAndTheStatusBar() {
        let viewModel = AppViewModel()
        XCTAssertNil(viewModel.errorMessage)

        viewModel.export.onError?("Export failed: disk full")

        XCTAssertEqual(viewModel.errorMessage, "Export failed: disk full",
                       "a hard failure should raise the alert")
        XCTAssertEqual(viewModel.statusMessage, "Export failed: disk full",
                       "...and also land in the status bar")
    }

    func testDeriveStatusAndErrorAreWired() {
        let viewModel = AppViewModel()

        viewModel.derive.onStatus?("Deriving recipe…")
        XCTAssertEqual(viewModel.statusMessage, "Deriving recipe…")

        viewModel.derive.onError?("Derive failed: bad pair")
        XCTAssertEqual(viewModel.errorMessage, "Derive failed: bad pair")
    }

    /// A finished derive should preview itself immediately — but only when
    /// there's an image on screen to preview it against.
    func testDerivedLUTIsSelectedWhenAnImageIsOpen() throws {
        let viewModel = AppViewModel()
        let lut = CubeLUT(cube: [SIMD3<Float>](repeating: .zero, count: 8), size: 2, name: "derived")

        viewModel.derive.onDerived?(lut)
        XCTAssertNil(viewModel.selectedLUT, "nothing to preview against yet")

        viewModel.sourceImage = CIImage(color: .gray)
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        viewModel.derive.onDerived?(lut)
        XCTAssertEqual(viewModel.selectedLUT, lut, "a derived LUT should preview on the open image")
    }

    func testDeriveSavePanelDefaultsToTheLUTFolder() async throws {
        let viewModel = AppViewModel()
        XCTAssertNil(viewModel.derive.libraryFolder?(), "no folder configured yet")

        viewModel.library.setFolder(tempDirectory)
        XCTAssertEqual(viewModel.derive.libraryFolder?(), tempDirectory,
                       "Save should open in the user's LUT folder")
    }

    /// Saving a derived LUT into the library folder has to trigger a re-scan,
    /// or the new file won't appear in the sidebar until relaunch.
    func testSavingADerivedLUTRescansTheLibrary() async throws {
        let viewModel = AppViewModel()
        viewModel.library.setFolder(tempDirectory)
        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(viewModel.library.allLUTs.isEmpty)

        // Drop a cube in and fire the saved hook the way DeriveCoordinator does.
        let saved = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Derived.cube", in: tempDirectory
        )
        viewModel.derive.onSaved?(saved)

        while viewModel.library.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(viewModel.library.allLUTs.map(\.name), ["Derived"],
                       "the sidebar should pick up a just-saved LUT without a relaunch")
    }

    // MARK: - Passthroughs

    func testExportFormatPassesThroughToTheCoordinator() {
        let viewModel = AppViewModel()
        XCTAssertEqual(viewModel.exportFormat, viewModel.export.format)

        viewModel.exportFormat = .tiff
        XCTAssertEqual(viewModel.export.format, .tiff,
                       "the toolbar picker writes through to the coordinator")
    }

    func testIsExportingReflectsTheCoordinator() {
        let viewModel = AppViewModel()
        XCTAssertFalse(viewModel.isExporting)
        XCTAssertEqual(viewModel.isExporting, viewModel.export.isExporting)
    }

    // MARK: - Export naming

    func testExportDialogNameUsesSourceAndLUT() throws {
        // Exercises the naming the export panel is seeded with, without the panel.
        let url = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "My Look.cube", in: tempDirectory
        )
        let lut = try CubeLUT(url: url)
        XCTAssertEqual(
            ExportCoordinator.defaultFileName(source: "R0010966", lut: lut, format: .jpeg),
            "R0010966_My_Look.jpg"
        )
    }

    // MARK: - Menu forwarding

    /// The menu bar reaches the app through notifications, so these forwards
    /// are the only thing connecting File ▸ Derive to the sheet.
    func testPresentAndDismissRecipeExtractorForwardToTheCoordinator() {
        let viewModel = AppViewModel()

        viewModel.presentRecipeExtractor()
        XCTAssertTrue(viewModel.derive.isSheetPresented)

        viewModel.dismissRecipeExtractor()
        XCTAssertFalse(viewModel.derive.isSheetPresented)
    }

    func testExportDialogWithNoImageTellsTheUserInsteadOfOpeningAPanel() {
        let viewModel = AppViewModel()
        XCTAssertNil(viewModel.sourceImage)

        // Must return without ever constructing a panel — if this hangs, the
        // guard has regressed and a modal is up.
        viewModel.exportDialog()
        XCTAssertEqual(viewModel.statusMessage, "Open an image first")
    }

    func testBatchExportWithNoImagesTellsTheUserInsteadOfOpeningAPanel() {
        let viewModel = AppViewModel()
        XCTAssertTrue(viewModel.collection.items.isEmpty)

        viewModel.batchExportDialog()
        XCTAssertEqual(
            viewModel.statusMessage,
            "Import a set of images first (Export All works on the filmstrip)"
        )
    }
}
