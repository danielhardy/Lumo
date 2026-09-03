import XCTest
import CoreImage
@testable import LumoKit

final class LookLUTExportTests: TempDirectoryTestCase {
    func testSupportMatrixIncludesVerifiedGlobalStagesAndOmitsSourceAndSpatialStages() {
        let document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 1),
            light: LightAdjustments(exposure: 0.5),
            color: ColorAdjustments(saturation: 20),
            effects: EffectsAdjustments(texture: 20, vignette: VignetteAdjustments(amount: 15), grain: GrainAdjustments(amount: 10)),
            crop: CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)),
            adjustments: [.vibrance(amount: 0.4)]
        )

        let matrix = LUTSupportMatrix.make(for: document)
        XCTAssertEqual(matrix.version, LUTSupportMatrix.currentVersion)
        XCTAssertTrue(matrix.included.map(\.id).contains(contentsOf: ["light", "color", "adjustment-0"]))
        XCTAssertTrue(matrix.omitted.map(\.id).contains(contentsOf: ["raw-develop", "spatial-effects", "vignette", "grain", "crop"]))
        XCTAssertTrue(matrix.omissionMessage?.contains("will be omitted") == true)
    }

    func testIdentityConversionProducesValidDocumentedCube() throws {
        let conversion = try LookLUTConverter.convert(document: EditDocument(), lut: nil, size: 2)
        XCTAssertEqual(conversion.cube.count, 8)
        XCTAssertTrue(conversion.verification.passed)
        let text = conversion.cubeText(title: "Identity Look")
        XCTAssertTrue(text.contains("LUT_3D_SIZE 2"))
        XCTAssertTrue(text.contains("Working color space: sRGB"))
        XCTAssertTrue(text.contains("DOMAIN_MIN: 0.0 0.0 0.0"))
        XCTAssertNotNil(try? CubeLUT(url: Fixtures.writeCube(text, named: "identity-look.cube", in: tempDirectory)))
    }

    func testDefaultLatticeUsesExactNormalizedCoordinates() throws {
        let conversion = try LookLUTConverter.convert(document: EditDocument(), lut: nil)
        let firstRedStep = conversion.cube[1].x

        XCTAssertEqual(firstRedStep, Float(1.0 / Float(LookLUTConverter.defaultSize - 1)), accuracy: 0.000001)
    }

    func testGlobalLightConversionRoundTripsThroughCubeWithinTolerance() throws {
        let document = EditDocument(light: LightAdjustments(exposure: 0.75, contrast: 22))
        let conversion = try LookLUTConverter.convert(document: document, lut: nil, size: 9)
        XCTAssertTrue(conversion.verification.passed)
        XCTAssertGreaterThan(conversion.verification.sampleCount, 0)
        XCTAssertFalse(conversion.cube.allSatisfy { $0 == SIMD3<Float>($0.x, $0.y, $0.z) && $0.x == 0 })
    }

    func testDefaultExportResolutionVerifiesARepresentativeColorEdit() throws {
        let document = EditDocument(color: ColorAdjustments(vibrance: 35, saturation: -12))
        let conversion = try LookLUTConverter.convert(document: document, lut: nil)
        XCTAssertEqual(conversion.size, LookLUTConverter.defaultSize)
        XCTAssertTrue(conversion.verification.passed)
    }

    func testDefaultExportKeepsNonlinearLightEditWithinTolerance() throws {
        let document = EditDocument(light: LightAdjustments(exposure: 0.75, contrast: 22, highlights: -18, shadows: 14))
        let conversion = try LookLUTConverter.convert(document: document, lut: nil)

        XCTAssertTrue(conversion.verification.passed)
        XCTAssertLessThanOrEqual(
            conversion.verification.maxAbsoluteChannelError,
            conversion.verification.tolerance
        )
    }

    @MainActor
    func testSaveRejectsCollisionAndDoesNotOverwriteExistingFile() throws {
        let coordinator = LookSaveCoordinator()
        let conversion = try LookLUTConverter.convert(document: EditDocument(), lut: nil, size: 2)
        coordinator.setConversion(conversion, name: "New Look")
        let destination = tempDirectory.appendingPathComponent("Existing.cube")
        try "sentinel".write(to: destination, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try coordinator.performSave(name: "New Look", to: destination)) { error in
            XCTAssertEqual((error as? LookSaveCoordinator.LookSaveError)?.errorDescription,
                           "A Look with that filename already exists. Choose a different name or destination.")
        }
        XCTAssertEqual(try String(contentsOf: destination), "sentinel")
    }

    @MainActor
    func testSavingRegistersWithoutChangingTheActiveDocument() async throws {
        let source = try Fixtures.writeGradientPNG(width: 8, height: 8, named: "save-look.png", in: tempDirectory)
        let store = EditDocumentStore(fileURL: tempDirectory.appendingPathComponent("edits.json"))
        let viewModel = AppViewModel(engine: FakeRenderEngine(), editStore: store)
        viewModel.openImage(url: source)
        let deadline = Date().addingTimeInterval(5)
        while viewModel.sourceName != source.lastPathComponent {
            if Date() > deadline { return XCTFail("timed out opening image") }
            try await Task.sleep(for: .milliseconds(10))
        }
        viewModel.updateDocument { $0.light.exposure = 0.5 }
        let before = viewModel.document
        let conversion = try LookLUTConverter.convert(document: before, lut: nil, size: 9)
        viewModel.lookSave.setConversion(conversion, name: "Saved Look")
        let destination = tempDirectory.appendingPathComponent("Saved Look.cube")
        try viewModel.lookSave.performSave(name: "Saved Look", to: destination)
        XCTAssertEqual(viewModel.document, before)
        XCTAssertEqual(viewModel.undoDepth, 1)
        viewModel.lookSave.onSaved?(destination)
        while viewModel.library.isImporting { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(viewModel.library.allLUTs.contains { $0.url == destination })
    }
}

private extension Array where Element: Equatable {
    func contains(contentsOf values: [Element]) -> Bool { values.allSatisfy(contains) }
}
