import XCTest
import CoreGraphics
@testable import LumoKit

/// Export policy is deliberately tested without presenting either export panel.
final class ExportOptionsTests: TempDirectoryTestCase {

    func testDefaultsAreFullSizeHighQualityAndSessionCompatible() throws {
        let options = ExportOptions.default

        XCTAssertEqual(options.format, .jpeg)
        XCTAssertEqual(options.sizing, .fullSize)
        XCTAssertEqual(options.quality, 0.95)
        XCTAssertEqual(options.colorSpace, .sRGB)
        XCTAssertEqual(options.bitDepth, .eight)
        XCTAssertEqual(options.alpha, .opaque)
        XCTAssertEqual(options.filenamePolicy, .sourceNameWithLook)
        XCTAssertEqual(options.metadata, .preserve)
        try options.validate()
    }

    func testCapabilityMatrixStatesPrecisionColorAndAlphaConstraints() {
        XCTAssertEqual(ExportFormat.tiff.capabilities.bitDepths, [.eight, .sixteen])
        XCTAssertEqual(ExportFormat.jpeg.capabilities.bitDepths, [.eight])
        XCTAssertEqual(ExportFormat.png.capabilities.bitDepths, [.eight, .sixteen])
        XCTAssertEqual(ExportFormat.jpeg.capabilities.alphaModes, [.opaque])
        XCTAssertTrue(ExportFormat.tiff.capabilities.supportsAlpha)
        XCTAssertTrue(ExportFormat.png.capabilities.colorSpaces.contains(.displayP3))
    }

    func testInvalidCombinationsFailBeforeRenderingWithActionableErrors() {
        let cases: [(ExportOptions, ExportOptionsError)] = [
            (
                ExportOptions(format: .jpeg, bitDepth: .sixteen),
                .unsupportedBitDepth(format: .jpeg, bitDepth: .sixteen)
            ),
            (
                ExportOptions(format: .jpeg, alpha: .preserve),
                .unsupportedAlpha(format: .jpeg, alpha: .preserve)
            ),
            (
                ExportOptions(format: .png, quality: 1.1),
                .invalidQuality(1.1)
            ),
            (
                ExportOptions(format: .png, sizing: .longEdge(0)),
                .invalidLongEdge(0)
            ),
        ]

        for (options, expected) in cases {
            XCTAssertThrowsError(try options.validate()) { error in
                XCTAssertEqual(error as? ExportOptionsError, expected)
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }

    func testRasterOutputWithExportOptionsReportsTheActualOutputKind() async throws {
        let options = ExportOptions(format: .jpeg)
        let request = RenderRequest(
            source: ImageSource(data: Data(), nativeExtent: CGSize(width: 1, height: 1)),
            document: EditDocument(),
            quality: .preview,
            output: .raster,
            exportOptions: options
        )

        do {
            _ = try await RenderEngine().render(request)
            XCTFail("Expected export options to reject raster output")
        } catch let error as ExportOptionsError {
            XCTAssertEqual(error, .outputRequiresEncoded(expected: .jpeg))
            XCTAssertEqual(
                error.errorDescription,
                "Export options request JPEG, but the render output is raster; export options require encoded output."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLongEdgeSizingPreservesAspectRatioAndDoesNotUpscaleOrientation() {
        let sizing = ExportSizing.longEdge(2000)
        XCTAssertEqual(
            sizing.outputSize(for: CGSize(width: 4000, height: 3000)),
            CGSize(width: 2000, height: 1500)
        )
        XCTAssertEqual(
            sizing.outputSize(for: CGSize(width: 3000, height: 4000)),
            CGSize(width: 1500, height: 2000),
            "portrait orientation must not be rotated by resize planning"
        )
        XCTAssertEqual(
            sizing.outputSize(for: CGSize(width: 1000, height: 800)),
            CGSize(width: 1000, height: 800),
            "a smaller source must not be enlarged"
        )
    }

    func testRenderEngineAppliesLongEdgePolicyAtExportTime() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 100, height: 50, named: "long-edge.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 100, height: 50))
        let options = ExportOptions(format: .png, sizing: .longEdge(40))
        let result = try await RenderEngine().render(RenderRequest(
            source: source,
            document: EditDocument(),
            quality: .export,
            output: .encoded(format: .png, quality: CGFloat(options.quality)),
            exportOptions: options
        ))

        XCTAssertEqual(result.extent, CGSize(width: 40, height: 20))
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 20)
    }

    func testRenderEngineMatchesPlannedDimensionsAtFractionalLongEdgeScale() async throws {
        let sourceExtent = CGSize(width: 3333, height: 5000)
        let url = try Fixtures.writeGradientPNG(
            width: Int(sourceExtent.width), height: Int(sourceExtent.height),
            named: "fractional-long-edge.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: sourceExtent)
        let options = ExportOptions(format: .png, sizing: .longEdge(2000))
        let result = try await RenderEngine().render(RenderRequest(
            source: source,
            document: EditDocument(),
            quality: .export,
            output: .encoded(format: .png, quality: CGFloat(options.quality)),
            exportOptions: options
        ))

        let planned = options.outputSize(for: sourceExtent)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(planned, CGSize(width: 1333, height: 2000))
        XCTAssertEqual(result.extent, planned)
        XCTAssertEqual(CGSize(width: image.width, height: image.height), planned)
    }

    func testRenderEngineDoesNotUpscaleSmallLongEdgeExports() async throws {
        let sourceExtent = CGSize(width: 100, height: 50)
        let url = try Fixtures.writeGradientPNG(
            width: Int(sourceExtent.width), height: Int(sourceExtent.height),
            named: "small-long-edge.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: sourceExtent)
        let options = ExportOptions(format: .png, sizing: .longEdge(200))
        let result = try await RenderEngine().render(RenderRequest(
            source: source,
            document: EditDocument(),
            quality: .export,
            output: .encoded(format: .png, quality: CGFloat(options.quality)),
            exportOptions: options
        ))

        XCTAssertEqual(result.extent, sourceExtent)
    }

    func testExportOptionsRoundTripAndRenderRequestStayValueOnly() throws {
        let options = ExportOptions(
            format: .tiff,
            sizing: .longEdge(2400),
            colorSpace: .displayP3,
            bitDepth: .sixteen,
            alpha: .preserve,
            filenamePolicy: .sourceName,
            destination: .folder(URL(fileURLWithPath: "/tmp/Exports")),
            metadata: .strip
        )
        let encoded = try JSONEncoder().encode(options)
        XCTAssertEqual(try JSONDecoder().decode(ExportOptions.self, from: encoded), options)

        let request = RenderRequest(
            source: ImageSource(data: Data(), nativeExtent: CGSize(width: 6000, height: 4000)),
            document: EditDocument(),
            quality: .export,
            output: .encoded(format: .tiff, quality: CGFloat(options.quality)),
            space: .sRGB,
            exportOptions: options
        )
        XCTAssertEqual(request.exportOptions, options)
        XCTAssertEqual(request.renderScale, .preview(maxSize: CGSize(width: 2400, height: 1600)))
    }

    func testFilenamePolicyIsIndependentOfTheExportPanel() {
        let options = ExportOptions(
            format: .png, filenamePolicy: .sourceNameWithLook
        )
        XCTAssertEqual(options.fileName(source: "DSC001", look: "Warm Look"), "DSC001_Warm_Look.png")
        XCTAssertEqual(
            ExportOptions(format: .png, filenamePolicy: .sourceName)
                .fileName(source: "DSC001", look: "Warm Look"),
            "DSC001.png"
        )
    }
}
