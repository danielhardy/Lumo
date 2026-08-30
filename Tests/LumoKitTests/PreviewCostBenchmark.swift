import XCTest
import CoreImage
import CoreGraphics
@testable import LumoKit

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

    /// The shape the app used before the cutover — grade an already-decoded image, then rasterize —
    /// reproduced here rather than called.
    ///
    /// Step 7 deleted `ImageProcessor.renderPreview` and `.export`, which is what these arms used to
    /// drive. Deleting the comparison with them would have been the easy move and the wrong one: the
    /// point of these numbers is that the engine stays within reach of a bare grade-and-rasterize,
    /// and that only stays measurable if the baseline survives its implementation. Six lines of
    /// Core Image is a cheap price for a regression signal that does not depend on shipped code.
    fileprivate static func baselineRasterize(
        _ image: CIImage, maxSize: CGSize, context: CIContext
    ) -> CGImage? {
        let extent = image.extent
        guard extent.isRasterizable else { return nil }
        let factor = min(maxSize.width / extent.width, maxSize.height / extent.height, 1.0)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        return context.createCGImage(scaled, from: scaled.extent.integral,
                                     format: .RGBA8, colorSpace: WorkingSpace.current.cgColorSpace)
    }

    fileprivate static func baselineEncodeJPEG(_ image: CIImage, context: CIContext) -> Data? {
        context.jpegRepresentation(
            of: image, colorSpace: WorkingSpace.current.cgColorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
        )
    }

    /// `time` for an async body. Runs the loop on a semaphore-free detached task and waits, so the
    /// per-render figure is comparable with the synchronous one.
    ///
    /// `@Sendable` because the body is handed to an unstructured `Task`: Swift 6 language mode
    /// rejects passing a non-sendable closure across that boundary. Every call site already captures
    /// only `Sendable` values — the actor, the source, the document, the cube — so this documents
    /// what was true rather than constraining anything.
    fileprivate func timeAsync(
        _ label: String, _ iterations: Int, unit: String = "render",
        _ body: @escaping @Sendable () async -> Void
    ) -> Double {
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
        print(String(format: "  %-46@ %7.1f ms/%@", label as NSString, each, unit as NSString))
        return each
    }

    func testMeasurePerRenderPreviewCost() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_BENCH"] != nil,
            "set LUMO_BENCH=1 to run the preview-cost measurement"
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
        let fullDecoded = try XCTUnwrap(ImageDecoder.developRAWNeutral(at: rawURL))
        _ = context.createCGImage(fullDecoded, from: fullDecoded.extent.integral,
                                  format: .RGBA8, colorSpace: WorkingSpace.current.cgColorSpace)
        let oneOffDecode = Date().timeIntervalSince(decodeStart) * 1000
        print(String(format: "  %-46@ %7.1f ms (once, at open)", "old: full-resolution decode" as NSString, oneOffDecode))

        let old = time("baseline: grade decoded image + rasterize", 5) {
            guard let graded = lut.apply(to: fullDecoded, intensity: 0.6) else { return }
            _ = Self.baselineRasterize(graded, maxSize: Self.previewBox, context: context)
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
            ProcessInfo.processInfo.environment["LUMO_BENCH"] != nil,
            "set LUMO_BENCH=1 to run the preview-cost measurement"
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
        let decoded = try XCTUnwrap(ImageDecoder.load(from: url))
        let old = time("baseline: grade decoded image + rasterize", 5) {
            guard let graded = lut.apply(to: decoded, intensity: 0.6) else { return }
            _ = Self.baselineRasterize(graded, maxSize: Self.previewBox, context: context)
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

    // MARK: - Export (Step 6)

    /// The same question for **export**, which Step 6 cut over.
    ///
    /// The preview cutover's trap was that Core Image caches decoded intermediates per `CIImage`
    /// instance, so rebuilding the source each render re-decoded the file — 150× on a big image. The
    /// engine answered that with a developed-source memo, and the memo covers **preview scales only**
    /// (§6). Export therefore rebuilds its source every time, deliberately, which is the exact shape
    /// of the regression Step 5 had to fix. Whether that is fine here is a measurement, not an
    /// argument: an export runs once per user action and already pays for a full-resolution decode
    /// and an encode, so the rebuild should disappear into the noise.
    ///
    /// The footprint reading is the other half, and it is a **comparison**, not a claim that nothing
    /// is retained. Both paths grow by roughly one full-resolution RGBA intermediate per export
    /// (~46 MB at 4000×3000) and neither gives it back — `CIContext.clearCaches()` does not reclaim
    /// it. That is Core Image's own accounting and it predates this cutover: measured back to back on
    /// twelve distinct images, the old `loadImage` + `apply` + `export` loop grew by exactly the same
    /// amount per file. What this run has to show is that the engine has not made it *worse*, which
    /// is what a memo accidentally added at `.full` would do.
    ///
    /// `swift test --filter PreviewCostBenchmark` with `LUMO_BENCH=1`.
    func testMeasureExportCost() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_BENCH"] != nil,
            "set LUMO_BENCH=1 to run the export-cost measurement"
        )
        let dir = try Fixtures.makeTempDirectory("bench-export")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try Fixtures.writeGradientPNG(width: 6000, height: 4000, named: "big.png", in: dir)

        let lut = TestImages.warmLUT()
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 6000, height: 4000))
        let document = EditDocument(
            adjustments: [.exposure(ev: 0.3)],
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.6)
        )
        let destination = dir.appendingPathComponent("out.jpg")

        func time(_ label: String, _ iterations: Int, _ body: () -> Void) -> Double {
            body()
            let start = Date()
            for _ in 0..<iterations { body() }
            let each = Date().timeIntervalSince(start) / Double(iterations) * 1000
            print(String(format: "  %-46@ %7.1f ms/export", label as NSString, each))
            return each
        }

        print("\n=== per-export cost, 6000x4000 PNG → JPEG ===")

        // Two baselines, because the two pre-cutover paths differed. The single export reused
        // `AppViewModel.sourceImage`, already decoded at open; the batch loop decoded per item and
        // paid for it every time. The engine always pays it, so only the second is apples to apples
        // — the first is the cost the single export moved. Note neither baseline sees `adjustments`,
        // which is the divergence Step 6 closed: the engine is doing strictly more work here.
        let context = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
        let decoded = try XCTUnwrap(ImageDecoder.load(from: url))
        let oldReusingDecode = time("baseline single: grade a decoded image + encode", 3) {
            guard let graded = lut.apply(to: decoded, intensity: 0.6),
                  let data = Self.baselineEncodeJPEG(graded, context: context) else { return }
            try? data.write(to: destination)
        }
        let old = time("baseline batch: decode + grade + encode", 3) {
            guard let fresh = try? ImageDecoder.load(from: url),
                  let graded = lut.apply(to: fresh, intensity: 0.6),
                  let data = Self.baselineEncodeJPEG(graded, context: context) else { return }
            try? data.write(to: destination)
        }

        let engine = RenderEngine()
        let new = timeAsync("new: engine.encode at .full (whole document)", 3, unit: "export") {
            guard let data = try? await engine.encode(
                source: source, document: document, lut: lut, scale: .full,
                format: .jpeg, quality: 0.95, space: .current
            ) else { return }
            try? data.write(to: destination)
        }
        print(String(format: "\n  engine vs baseline batch (both decode):   %.2fx", new / old))
        print(String(format: "  engine vs baseline single (decode reused): %.2fx", new / oldReusingDecode))

        // Footprint, both paths, over a run of *distinct* images — a batch export, in other words.
        // The two should track each other; a divergence means one of them started holding on to
        // full-resolution intermediates the other doesn't.
        print("\n=== footprint over 8 distinct 4000x3000 exports ===")
        var batch: [ImageSource] = []
        for i in 0..<8 {
            let u = try Fixtures.writeGradientPNG(width: 4000, height: 3000, named: "b\(i).png", in: dir)
            batch.append(ImageSource(url: u, nativeExtent: CGSize(width: 4000, height: 3000)))
        }

        let oldStart = Self.footprintMB()
        for item in batch {
            guard case .url(let u) = item.backing,
                  let decoded = try? ImageDecoder.load(from: u),
                  let graded = lut.apply(to: decoded, intensity: 0.6),
                  let data = Self.baselineEncodeJPEG(graded, context: context) else { continue }
            try? data.write(to: destination)
        }
        let oldEnd = Self.footprintMB()

        let engineForBatch = RenderEngine()
        let newStart = Self.footprintMB()
        let group = DispatchGroup()
        group.enter()
        Task {
            for item in batch {
                _ = try? await engineForBatch.encode(
                    source: item, document: document, lut: lut, scale: .full,
                    format: .jpeg, quality: 0.95, space: .current
                )
            }
            group.leave()
        }
        group.wait()
        let newEnd = Self.footprintMB()

        print(String(format: "  baseline:  %.0f → %.0f MB  (%+.0f, %.0f MB/export)",
                     oldStart, oldEnd, oldEnd - oldStart, (oldEnd - oldStart) / 8))
        print(String(format: "  engine:    %.0f → %.0f MB  (%+.0f, %.0f MB/export)\n",
                     newStart, newEnd, newEnd - newStart, (newEnd - newStart) / 8))
    }

    /// Resident footprint in MB. Same instrument the derive memory work used — a number, not a
    /// claim about what Core Image holds.
    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return .nan }
        return Double(info.phys_footprint) / (1024 * 1024)
    }
}
