import XCTest
import CoreImage
import CoreGraphics
@testable import LUTzyKit

/// Not an assertion — a measurement, kept because the number it produces decides a design question
/// that is otherwise guesswork.
///
/// Cutting the preview over changes *when* a RAW is demosaiced. Today the file is decoded once at
/// full resolution and every subsequent LUT or intensity change reuses that decoded image. After the
/// cutover each preview render re-develops the RAW from bytes at preview scale, because
/// `CIRAWFilter` has to be rebuilt to honour `rawDevelop` (§4.2).
///
/// That trade is only worth making if a preview-scale develop is *cheaper* than a full-resolution
/// grade — otherwise dragging the intensity slider gets slower, which is a regression a user would
/// feel immediately.
///
/// Skipped without a local RAW, and skipped by default besides: run it deliberately with
/// `swift test --filter PreviewCostBenchmark`.
final class PreviewCostBenchmark: XCTestCase {

    private static let previewBox = CGSize(width: 1600, height: 1200)

    /// `time` for an async body. Runs the loop on a semaphore-free detached task and waits, so the
    /// per-render figure is comparable with the synchronous one.
    fileprivate func timeAsync(_ label: String, _ iterations: Int, _ body: @escaping () async -> Void) -> Double {
        func runAll() {
            let group = DispatchGroup()
            group.enter()
            Task { await body(); group.leave() }
            group.wait()
        }
        runAll()
        let start = Date()
        for _ in 0..<iterations { runAll() }
        let each = Date().timeIntervalSince(start) / Double(iterations) * 1000
        print(String(format: "  %-46@ %7.1f ms/render", label as NSString, each))
        return each
    }

    func testMeasurePerRenderPreviewCost() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUTZY_BENCH"] != nil,
            "set LUTZY_BENCH=1 to run the preview-cost measurement"
        )
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW; see Fixtures.localRAWURL")
        }

        let context = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
        let lut = TestImages.warmLUT()
        let source = ImageSource(url: rawURL, nativeExtent: .zero)
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 0.6))
        let cache = LUTFilterCache()

        func time(_ label: String, _ iterations: Int, _ body: () -> Void) -> Double {
            body()  // warm up; the first call pays for shader compilation
            let start = Date()
            for _ in 0..<iterations { body() }
            let each = Date().timeIntervalSince(start) / Double(iterations) * 1000
            print(String(format: "  %-46@ %7.1f ms/render", label as NSString, each))
            return each
        }

        print("\n=== per-render preview cost, \(rawURL.lastPathComponent) ===")

        // The old path: decode once up front, then grade + rasterize the decoded image per render.
        let decodeStart = Date()
        let fullDecoded = try XCTUnwrap(ImageProcessor.developRAWNeutral(at: rawURL))
        _ = context.createCGImage(fullDecoded, from: fullDecoded.extent.integral,
                                  format: .RGBA8, colorSpace: WorkingSpace.current.cgColorSpace)
        let oneOffDecode = Date().timeIntervalSince(decodeStart) * 1000
        print(String(format: "  %-46@ %7.1f ms (once, at open)", "old: full-resolution decode" as NSString, oneOffDecode))

        let old = time("old: grade decoded image + rasterize preview", 5) {
            guard let graded = lut.apply(to: fullDecoded, intensity: 0.6) else { return }
            _ = ImageProcessor.shared.renderPreview(graded, maxSize: Self.previewBox)
        }

        // The new path: re-develop at preview scale, grade, rasterize — all per render.
        let new = time("new: pipeline at preview scale + rasterize", 5) {
            guard let image = RenderPipeline.buildImage(
                source: source, document: document, lut: lut,
                scale: .preview(maxSize: Self.previewBox), space: .current, lutCache: cache
            ) else { return }
            _ = context.createCGImage(image, from: image.extent.integral,
                                      format: .RGBA8, colorSpace: WorkingSpace.current.cgColorSpace)
        }

        // And through the engine, which memoizes the developed source — the shipping path.
        let engine = RenderEngine()
        let viaEngine = timeAsync("new: through RenderEngine (memoized source)", 5) {
            _ = await engine.makeCGImage(
                source: source, document: document, lut: lut,
                scale: .preview(maxSize: Self.previewBox), space: .current
            )
        }

        print(String(format: "\n  bare pipeline vs old:  %.2fx", new / old))
        print(String(format: "  engine vs old:         %.2fx    (open cost saved: %.0f ms)\n",
                     viaEngine / old, oneOffDecode))
    }

    /// The same question for a standard image. `CIImage(contentsOf:)` is lazy, so the *construction*
    /// is cheap — but the decode still happens at render time, and doing it per render rather than
    /// once could regress just as badly. Assuming otherwise would be exactly the kind of guess this
    /// file exists to replace.
    func testMeasurePerRenderPreviewCostForAStandardImage() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUTZY_BENCH"] != nil,
            "set LUTZY_BENCH=1 to run the preview-cost measurement"
        )
        // A big JPEG, sized like something off a camera rather than a fixture.
        let dir = try Fixtures.makeTempDirectory("bench")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try Fixtures.writeGradientPNG(width: 6000, height: 4000, named: "big.png", in: dir)

        let context = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
        let lut = TestImages.warmLUT()
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 6000, height: 4000))
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 0.6))
        let cache = LUTFilterCache()

        func time(_ label: String, _ iterations: Int, _ body: () -> Void) -> Double {
            body()
            let start = Date()
            for _ in 0..<iterations { body() }
            let each = Date().timeIntervalSince(start) / Double(iterations) * 1000
            print(String(format: "  %-46@ %7.1f ms/render", label as NSString, each))
            return each
        }

        print("\n=== per-render preview cost, 6000x4000 PNG ===")
        let decoded = try XCTUnwrap(ImageProcessor.shared.loadImage(from: url))
        let old = time("old: grade decoded image + rasterize preview", 5) {
            guard let graded = lut.apply(to: decoded, intensity: 0.6) else { return }
            _ = ImageProcessor.shared.renderPreview(graded, maxSize: Self.previewBox)
        }
        let new = time("new: pipeline at preview scale + rasterize", 5) {
            guard let image = RenderPipeline.buildImage(
                source: source, document: document, lut: lut,
                scale: .preview(maxSize: Self.previewBox), space: .current, lutCache: cache
            ) else { return }
            _ = context.createCGImage(image, from: image.extent.integral,
                                      format: .RGBA8, colorSpace: WorkingSpace.current.cgColorSpace)
        }
        let engine = RenderEngine()
        let viaEngine = timeAsync("new: through RenderEngine (memoized source)", 5) {
            _ = await engine.makeCGImage(
                source: source, document: document, lut: lut,
                scale: .preview(maxSize: Self.previewBox), space: .current
            )
        }
        print(String(format: "\n  bare pipeline vs old:  %.2fx", new / old))
        print(String(format: "  engine vs old:         %.2fx\n", viaEngine / old))
    }
}
