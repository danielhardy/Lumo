import XCTest
import CoreGraphics
import ImageIO
@testable import LumoKit

/// Contract tests for the UI-independent render funnel introduced in LUMO-012.
final class RenderRequestTests: TempDirectoryTestCase {

    private func makeSource() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "request.png", in: tempDirectory
        )
        return ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
    }

    private func decodedSize(_ data: Data) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    func testAllFiveQualityTiersAreRepresented() {
        XCTAssertEqual(
            RenderQuality.allCases,
            [.thumbnail, .interactive, .preview, .fullResolution, .export]
        )
    }

    func testQualityControlsExtentWithoutChangingTheEditModel() async throws {
        let source = try makeSource()
        let document = EditDocument(adjustments: [.exposure(ev: 0.35)])
        let engine = RenderEngine()
        let downsampled: [RenderQuality] = [.thumbnail, .interactive, .preview]

        for quality in downsampled {
            let result = try await engine.render(RenderRequest(
                source: source, document: document, targetSize: CGSize(width: 24, height: 24),
                quality: quality, output: .raster
            ))
            XCTAssertEqual(result.quality, quality)
            XCTAssertEqual(result.extent, CGSize(width: 24, height: 16))
            XCTAssertEqual(try decodedSize(result.data), result.extent)
        }

        for quality in [RenderQuality.fullResolution, .export] {
            let result = try await engine.render(RenderRequest(
                source: source, document: document, targetSize: CGSize(width: 24, height: 24),
                quality: quality, output: .raster
            ))
            XCTAssertEqual(result.extent, CGSize(width: 96, height: 64))
            XCTAssertEqual(try decodedSize(result.data), result.extent)
        }
    }

    func testNeutralRenderBakesOrientationAndReportsTheEncodedExtent() async throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "oriented.jpg", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 60, height: 80))
        let result = try await RenderEngine().render(RenderRequest(
            source: source, document: EditDocument(), quality: .fullResolution, output: .raster
        ))

        XCTAssertEqual(result.extent, CGSize(width: 60, height: 80))
        XCTAssertEqual(try decodedSize(result.data), CGSize(width: 60, height: 80))
        XCTAssertEqual(result.colorSpace, .current)
    }

    func testPreviewAndExportParityUsesExplicitQualityAndOutputPolicies() async throws {
        let source = try makeSource()
        // Construct the grade through the same mapping a visual wheel uses. The request funnel must
        // preserve that state identically for an on-screen preview and a lossless export.
        let document = EditDocument(
            color: ColorAdjustments(grading: ColorGradingAdjustments(
                midtones: ColorGradingWheelMapping.wheel(at: .init(x: -0.4, y: 0.7))
            )),
            adjustments: [.vibrance(amount: 0.4)]
        )
        let engine = RenderEngine()

        let preview = try await engine.render(RenderRequest(
            source: source, document: document, targetSize: source.nativeExtent,
            quality: .preview, output: .raster, space: .displayP3
        ))
        let export = try await engine.render(RenderRequest(
            source: source, document: document,
            quality: .export,
            output: .encoded(format: .png, quality: 1), space: .displayP3
        ))

        XCTAssertEqual(preview.output, .raster)
        XCTAssertEqual(export.output, .encoded(format: .png, quality: 1))
        XCTAssertEqual(preview.colorSpace, export.colorSpace)
        XCTAssertEqual(preview.extent, export.extent)
        assertPixelsEqual(
            try Pixels.bytes(of: try Pixels.decode(preview.data)),
            try Pixels.bytes(of: try Pixels.decode(export.data)),
            "preview and export request policies must preserve the same pipeline pixels"
        )
    }
}
