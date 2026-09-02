import XCTest
import CoreImage
import CoreGraphics
import Metal
import UniformTypeIdentifiers
@testable import LumoKit

/// Phase 2 Step 4. The engine is the only thing in the stack that owns a `CIContext`, so what is
/// worth pinning is the boundary rather than the arithmetic — the pipeline's maths already has its
/// own suite.
///
/// The headline property is **preview/export parity**. Today `renderPreview` and `export` are two
/// code paths that merely agree; after the cutover they are one `buildImage` call and one rasterizer,
/// differing only in `RenderScale`. This is where that stops being an aspiration.
final class RenderEngineTests: TempDirectoryTestCase {

    private var sourceURL: URL!
    private var source: ImageSource!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sourceURL = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "src.png", in: tempDirectory)
        source = ImageSource(url: sourceURL, nativeExtent: CGSize(width: 96, height: 64))
    }

    /// `XCTUnwrap` takes an autoclosure, which cannot contain `await` — so the actor hop happens
    /// here and the unwrap happens after it.
    private func render(
        _ engine: RenderEngine,
        _ document: EditDocument,
        lut: CubeLUT? = nil,
        scale: RenderScale = .full,
        space: WorkingSpace = .current
    ) async throws -> CGImage {
        let image = await engine.makeCGImage(
            source: source, document: document, lut: lut, scale: scale, space: space
        )
        return try XCTUnwrap(image)
    }

    // MARK: - Parity

    /// Display previews cross the actor boundary as completed GPU pixels, not as a lazy graph.
    /// The color-space metadata is retained on the texture-backed image so the presentation pass
    /// cannot silently fall back to the context's default space.
    func testDisplayPreviewIsBackedByACompletedMetalTexture() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let engine = RenderEngine()
        let request = RenderRequest(
            source: source, document: EditDocument(),
            targetSize: CGSize(width: 48, height: 48), quality: .preview, output: .raster
        )
        let maybeImage = await engine.makeCIImage(request)
        let image = try XCTUnwrap(maybeImage)

        XCTAssertEqual(image.colorSpace?.name as String?, CGColorSpace.sRGB as String?)
        XCTAssertEqual(image.extent.integral.size, CGSize(width: 48, height: 32))
        let displayed = try await MainActor.run {
            try XCTUnwrap(
                RenderEngine.presentationContext.createCGImage(image, from: image.extent.integral),
                "the completed texture must remain consumable by a Core Image presenter"
            )
        }
        let reference = try await render(
            engine, EditDocument(), scale: .preview(maxSize: CGSize(width: 48, height: 48))
        )
        assertPixelsEqual(try Pixels.bytes(of: displayed), try Pixels.bytes(of: reference),
                          "completed preview pixels must match the actor-owned raster path")
    }

    /// RAW develop edits must survive the completed-texture boundary, not only the lazy graph path.
    func testCompletedRAWPreviewReflectsDevelopSettings() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }
        let rawSource = ImageSource(url: rawURL, nativeExtent: CGSize(width: 4000, height: 3000))
        let engine = RenderEngine()

        func preview(_ settings: RAWDevelopSettings) async throws -> [UInt8] {
            let request = RenderRequest(
                source: rawSource, document: EditDocument(rawDevelop: settings),
                targetSize: CGSize(width: 256, height: 256), quality: .preview, output: .raster
            )
            let maybeImage = await engine.makeCIImage(request)
            let image = try XCTUnwrap(maybeImage)
            let cgImage = try await MainActor.run {
                try XCTUnwrap(RenderEngine.presentationContext.createCGImage(image, from: image.extent.integral))
            }
            return try Pixels.bytes(of: cgImage)
        }

        let neutral = try await preview(.neutral)
        let exposed = try await preview(RAWDevelopSettings(exposure: 1.5))
        assertPixelsDiffer(exposed, neutral, "completed RAW previews must carry develop changes")
    }

    /// The whole point of Phase 2, asserted directly: the same document rendered for display and
    /// encoded for export must be the same pixels. Not "close" — the same graph, the same rasterizer,
    /// one scale value apart.
    ///
    /// PNG because it is lossless; a JPEG comparison would be measuring the encoder.
    func testPreviewAndExportAreTheSamePixels() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(
            light: LightAdjustments(
                contrast: 35, highlights: -25, shadows: 40, whites: 30, blacks: -20,
                toneCurve: LightToneCurve(points: [
                    LightCurvePoint(input: 0.25, output: 0.12),
                    LightCurvePoint(input: 0.5, output: 0.58),
                    LightCurvePoint(input: 0.75, output: 0.88),
                ])),
            color: ColorAdjustments(
                vibrance: 35,
                saturation: -20,
                mixer: ColorMixerAdjustments(
                    red: ColorMixerChannel(hue: 18, saturation: -12, luminance: 8),
                    blue: ColorMixerChannel(hue: -22, saturation: 20, luminance: -10)
                ),
                grading: ColorGradingAdjustments(
                    shadows: ColorGradingWheel(hue: 220, saturation: 24),
                    midtones: ColorGradingWheel(hue: 35, saturation: 18),
                    highlights: ColorGradingWheel(hue: 10, saturation: 20),
                    blending: 65,
                    balance: -12
                )
            ),
            effects: EffectsAdjustments(
                texture: 55, clarity: 45, dehaze: 35,
                vignette: VignetteAdjustments(
                    amount: 62, midpoint: 44, roundness: -35, feather: 68, highlights: 48
                ),
                grain: GrainAdjustments(amount: 64, size: 58, roughness: 72)
            ),
            adjustments: [.exposure(ev: 0.3), .vibrance(amount: 0.4)],
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.8)
        )

        let preview = try await render(engine, document, lut: lut)
        let exported = try await engine.encode(
            source: source, document: document, lut: lut, scale: .full,
            format: .png, quality: 1, space: .current
        )
        let decoded = try Pixels.decode(exported)

        XCTAssertEqual(preview.width, decoded.width)
        XCTAssertEqual(preview.height, decoded.height)
        assertPixelsEqual(try Pixels.bytes(of: preview), try Pixels.bytes(of: decoded),
                          "preview and export must rasterize to the same pixels")
    }

    func testExportMetadataPolicyRoundTripsSourceMetadataForEveryFormat() async throws {
        let url = try Fixtures.writeJPEG(
            named: "metadata-source.jpg",
            in: tempDirectory,
            exif: [
                kCGImagePropertyExifLensModel: "Lumo Prime 35mm",
                kCGImagePropertyExifDateTimeOriginal: "2026:09:02 12:34:56",
            ],
            tiff: [
                kCGImagePropertyTIFFMake: "Lumo",
                kCGImagePropertyTIFFModel: "Test Body",
                kCGImagePropertyTIFFSoftware: "Lumo Tests",
            ],
            gps: [
                kCGImagePropertyGPSLatitude: 43.6150,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 116.2023,
                kCGImagePropertyGPSLongitudeRef: "W",
            ]
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 64, height: 48))
        let engine = RenderEngine()

        for format in ExportFormat.allCases {
            let result = try await engine.encode(
                source: source,
                document: EditDocument(),
                lut: nil,
                options: ExportOptions(format: format, metadata: .preserve)
            )
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
            )
            let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
            let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
            let gps = try XCTUnwrap(properties[kCGImagePropertyGPSDictionary] as? [CFString: Any])

            XCTAssertEqual(exif[kCGImagePropertyExifLensModel] as? String, "Lumo Prime 35mm", format.rawValue)
            XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal] as? String, "2026:09:02 12:34:56", format.rawValue)
            XCTAssertEqual(tiff[kCGImagePropertyTIFFMake] as? String, "Lumo", format.rawValue)
            XCTAssertEqual(tiff[kCGImagePropertyTIFFModel] as? String, "Test Body", format.rawValue)
            XCTAssertEqual(tiff[kCGImagePropertyTIFFSoftware] as? String, "Lumo Tests", format.rawValue)
            let latitude = try XCTUnwrap(gps[kCGImagePropertyGPSLatitude] as? Double)
            let longitude = try XCTUnwrap(gps[kCGImagePropertyGPSLongitude] as? Double)
            XCTAssertEqual(latitude, 43.6150, accuracy: 0.0001, format.rawValue)
            XCTAssertEqual(longitude, 116.2023, accuracy: 0.0001, format.rawValue)
        }
    }

    func testStripMetadataDoesNotCopySourcePhotographicDictionaries() async throws {
        let url = try Fixtures.writeJPEG(
            named: "metadata-strip-source.jpg",
            in: tempDirectory,
            exif: [kCGImagePropertyExifLensModel: "Lumo Prime 35mm"],
            tiff: [kCGImagePropertyTIFFMake: "Lumo", kCGImagePropertyTIFFModel: "Test Body"],
            gps: [kCGImagePropertyGPSLatitude: 43.6150, kCGImagePropertyGPSLongitude: 116.2023]
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 64, height: 48))
        let engine = RenderEngine()

        for format in ExportFormat.allCases {
            let result = try await engine.encode(
                source: source,
                document: EditDocument(),
                lut: nil,
                options: ExportOptions(format: format, metadata: .strip)
            )
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
            )
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
            XCTAssertNil(exif?[kCGImagePropertyExifLensModel], format.rawValue)
            XCTAssertNil(tiff?[kCGImagePropertyTIFFMake], format.rawValue)
            XCTAssertNil(tiff?[kCGImagePropertyTIFFModel], format.rawValue)
            XCTAssertNil(gps?[kCGImagePropertyGPSLatitude], format.rawValue)
            XCTAssertNil(gps?[kCGImagePropertyGPSLongitude], format.rawValue)
        }
    }

    func testPreservedMetadataDoesNotReapplySourceOrientation() async throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6,
            named: "oriented-metadata-source.jpg", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 60, height: 80))
        let result = try await RenderEngine().encode(
            source: source,
            document: EditDocument(),
            lut: nil,
            options: ExportOptions(format: .jpeg, metadata: .preserve)
        )
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        )

        XCTAssertEqual(Fixtures.storedSize(of: write(result, named: "oriented-output.jpg")),
                       CGSize(width: 60, height: 80))
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
        XCTAssertTrue(orientation != 6)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let tiffOrientation = (tiff?[kCGImagePropertyTIFFOrientation] as? NSNumber)?.intValue
        XCTAssertTrue(tiffOrientation != 6)
    }

    private func write(_ data: Data, named name: String) -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }

    /// And parity has to hold in a *non-default* space, or the test above would pass for a pipeline
    /// that hard-coded sRGB in both halves — which is precisely the bug Step 1 fixed.
    func testParityHoldsInEveryWorkingSpace() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1))

        for space in WorkingSpace.allCases {
            let preview = try await render(engine, document, lut: lut, space: space)
            let exported = try await engine.encode(
                source: source, document: document, lut: lut, scale: .full,
                format: .png, quality: 1, space: space
            )
            assertPixelsEqual(try Pixels.bytes(of: preview),
                              try Pixels.bytes(of: try Pixels.decode(exported)),
                              "preview and export disagree in \(space.rawValue)")
        }
    }

    /// The engine rasterizes exactly the graph `RenderPipeline` builds — it does not resize, crop or
    /// re-grade on the way out.
    ///
    /// Run in **both** spaces on purpose. Parity alone cannot catch an engine that passes the wrong
    /// space to the graph builder, because both halves would then be wrong *together* and still agree
    /// with each other — which is exactly what a mutation demonstrated. Comparing against a graph
    /// built independently in the same space is what pins the interpolation half.
    func testTheEngineRasterizesThePipelineGraphUnchanged() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(
            adjustments: [.colorControls(brightness: 0.1, contrast: 1.3, saturation: 0.7)],
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.5)
        )

        for space in WorkingSpace.allCases {
            let viaEngine = try await render(engine, document, lut: lut, space: space)
            let graph = try XCTUnwrap(RenderPipeline.buildImage(
                source: source, document: document, lut: lut, scale: .full, space: space
            ))

            assertPixelsEqual(try Pixels.bytes(of: viaEngine),
                              try Pixels.bytes(of: graph, space: space),
                              "the engine should evaluate the graph unchanged in \(space.rawValue)")
        }
    }

    /// And the cube really is interpolated in the requested space when driven through the engine —
    /// the same assertion Step 3 makes of the pipeline, repeated here because the engine is a second
    /// place the argument could be dropped.
    func testTheWorkingSpaceReachesTheCubeThroughTheEngine() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1))

        // Both graphs rasterized through sRGB, so only the interpolation differs.
        let inSRGB = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: document, lut: lut, scale: .full, space: .sRGB
        ))
        let inP3 = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: document, lut: lut, scale: .full, space: .displayP3
        ))
        assertPixelsDiffer(try Pixels.bytes(of: inSRGB, space: .sRGB),
                           try Pixels.bytes(of: inP3, space: .sRGB),
                           "the interpolation space must change the cube's result")

        // The engine's own output in each space must match its corresponding graph.
        let engineSRGB = try await render(engine, document, lut: lut, space: .sRGB)
        assertPixelsEqual(try Pixels.bytes(of: engineSRGB), try Pixels.bytes(of: inSRGB, space: .sRGB),
                          "the engine's sRGB render should match an sRGB-interpolated graph")
    }

    // MARK: - Scale

    func testScaleIsTheOnlyDifferenceBetweenPreviewAndFull() async throws {
        let engine = RenderEngine()

        let full = try await render(engine, EditDocument())
        let preview = try await render(
            engine, EditDocument(), scale: .preview(maxSize: CGSize(width: 32, height: 32))
        )

        XCTAssertEqual(full.width, 96)
        XCTAssertEqual(full.height, 64)
        XCTAssertLessThanOrEqual(preview.width, 32)
        XCTAssertLessThanOrEqual(preview.height, 32)
        XCTAssertGreaterThan(preview.width, 0)
    }

    // MARK: - Encoding

    func testEveryFormatEncodesToItsOwnType() async throws {
        let engine = RenderEngine()
        let expected: [ExportFormat: UTType] = [
            .png: .png, .jpeg: .jpeg, .tiff: .tiff,
        ]

        for (format, type) in expected {
            let data = try await engine.encode(
                source: source, document: EditDocument(), lut: nil, scale: .full,
                format: format, quality: 0.95, space: .current
            )
            XCTAssertFalse(data.isEmpty, "\(format) produced no bytes")

            let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let uti = try XCTUnwrap(CGImageSourceGetType(imageSource) as String?)
            XCTAssertEqual(UTType(uti), type, "\(format) encoded as \(uti)")
        }
    }

    /// The output-encoding half of the colour seam has to reach the encoder — if it were dropped,
    /// both files would carry the same profile.
    func testTheWorkingSpaceReachesTheEncoder() async throws {
        let engine = RenderEngine()

        let sRGB = try await engine.encode(
            source: source, document: EditDocument(), lut: nil, scale: .full,
            format: .png, quality: 1, space: .sRGB
        )
        let p3 = try await engine.encode(
            source: source, document: EditDocument(), lut: nil, scale: .full,
            format: .png, quality: 1, space: .displayP3
        )

        let sRGBName = try Pixels.decode(sRGB).colorSpace?.name as String?
        let p3Name = try Pixels.decode(p3).colorSpace?.name as String?
        XCTAssertEqual(sRGBName, CGColorSpace.sRGB as String)
        XCTAssertEqual(p3Name, CGColorSpace.displayP3 as String)
        XCTAssertNotEqual(sRGBName, p3Name)
    }

    // MARK: - Failure

    func testAnUndecodableSourceIsNilForPreviewAndThrowsForExport() async throws {
        let engine = RenderEngine()
        let junk = ImageSource(backing: .data(Data("not an image".utf8)), kind: .standard, nativeExtent: .zero)

        let preview = await engine.makeCGImage(
            source: junk, document: EditDocument(), lut: nil, scale: .full, space: .current
        )
        XCTAssertNil(preview)

        do {
            _ = try await engine.encode(
                source: junk, document: EditDocument(), lut: nil, scale: .full,
                format: .png, quality: 1, space: .current
            )
            XCTFail("encoding an undecodable source should throw")
        } catch {
            // Assert on *which* failure: an unrelated error would satisfy a bare `catch`. Matched
            // by pattern rather than by `==` so `ImageError` doesn't need an `Equatable` conformance
            // it has no other use for.
            guard case ImageError.processingFailed = error else {
                return XCTFail("expected processingFailed, got \(error)")
            }
        }
    }

    // MARK: - The developed-source memo

    /// The memo exists so an intensity drag does not re-decode the file every frame (measured: 156 ms
    /// versus 0.6 ms on a 6000×4000 source). It must not be observable in the output.
    ///
    /// Two *different preview sizes* on purpose: a memo keyed on everything but the scale would
    /// serve the first size's image for the second, which a single preview render cannot detect.
    func testTheMemoIsKeyedOnThePreviewSize() async throws {
        let engine = RenderEngine()

        let small = try await render(engine, EditDocument(),
                                     scale: .preview(maxSize: CGSize(width: 32, height: 32)))
        let large = try await render(engine, EditDocument(),
                                     scale: .preview(maxSize: CGSize(width: 64, height: 64)))

        XCTAssertLessThanOrEqual(small.width, 32)
        XCTAssertEqual(large.width, 64, "a second preview size must not reuse the first's image")
        XCTAssertNotEqual(small.width, large.width)
    }

    /// And keyed on the image. A memo that ignored which source it held would keep showing the
    /// previous photo after the user stepped to the next one — invisible to any test that only ever
    /// opens one image.
    func testTheMemoIsKeyedOnTheSource() async throws {
        let engine = RenderEngine()
        let box = RenderScale.preview(maxSize: CGSize(width: 48, height: 48))

        let firstURL = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "a.png", in: tempDirectory)
        // A solid patch, so the two images cannot be confused for one another.
        let secondURL = tempDirectory.appendingPathComponent("b.png")
        let solid = try Fixtures.makeCGImage(width: 96, height: 64, red: 0.1, green: 0.9, blue: 0.2)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(
            secondURL as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(dest, solid, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let a = ImageSource(url: firstURL, nativeExtent: CGSize(width: 96, height: 64))
        let b = ImageSource(url: secondURL, nativeExtent: CGSize(width: 96, height: 64))

        let imageA = await engine.makeCGImage(
            source: a, document: EditDocument(), lut: nil, scale: box, space: .current
        )
        let imageB = await engine.makeCGImage(
            source: b, document: EditDocument(), lut: nil, scale: box, space: .current
        )
        let renderedA = try XCTUnwrap(imageA)
        let renderedB = try XCTUnwrap(imageB)

        assertPixelsDiffer(try Pixels.bytes(of: renderedB), try Pixels.bytes(of: renderedA),
                           "opening a second image must not keep serving the first")
    }

    // MARK: - The cache lives on the actor

    /// The cube filter is built once and reused across renders. Invisible in the output by design, so
    /// it is observed through the count — a silently-bypassed cache would be pure cost.
    func testTheCubeFilterIsBuiltOnceAndReused() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1))

        let initialCount = await engine.cachedFilterCount
        XCTAssertEqual(initialCount, 0)

        for _ in 0..<5 {
            _ = await engine.makeCGImage(
                source: source, document: document, lut: lut, scale: .full, space: .current
            )
        }
        let afterFive = await engine.cachedFilterCount
        XCTAssertEqual(afterFive, 1, "five renders of one LUT should build one filter")

        // A second space is a second entry — the cube is interpolated in the space.
        _ = await engine.makeCGImage(
            source: source, document: document, lut: lut, scale: .full, space: .displayP3
        )
        let afterP3 = await engine.cachedFilterCount
        XCTAssertEqual(afterP3, 2)

        await engine.invalidateLUTCache()
        let afterFlush = await engine.cachedFilterCount
        XCTAssertEqual(afterFlush, 0, "a rescan must be able to drop stale cubes")
    }

    func testInvalidatingLUTsAlsoDropsAResolvedPreview() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let request = RenderRequest(
            source: source, document: EditDocument(lut: LUTSettings(lutID: lut.lutID)),
            lut: lut, targetSize: CGSize(width: 32, height: 32), quality: .preview
        )

        _ = try await engine.render(request)
        let before = await engine.cacheStatistics()
        XCTAssertEqual(before.preview.count, 1)

        await engine.invalidateLUTCache()
        let after = await engine.cacheStatistics()
        XCTAssertEqual(after.preview.count, 0,
                       "a LUT refresh must not leave an old final preview cached")
    }

    /// The staleness the cache flush exists to prevent, asserted in **pixels** rather than in counts.
    ///
    /// A `LUTID` is a file path, so replacing a `.cube` in place gives a different cube under an
    /// unchanged identity. Step 9 made that reachable from the UI: save a derive to `X.cube`, derive
    /// again, save over `X.cube`. Without the flush the engine serves the first cube forever and the
    /// second save appears to do nothing.
    ///
    /// The count-based test above would pass against a flush that dropped entries and rebuilt them
    /// from a stale table, so this one drives the whole path and looks at the output. The two renders
    /// are interleaved in one process, per the repo's Core Image reproducibility rule.
    func testAReplacedCubeAtTheSamePathRendersTheNewLookAfterAFlush() async throws {
        let engine = RenderEngine()
        let path = tempDirectory.appendingPathComponent("Look.cube")

        try Fixtures.writeCube(Fixtures.identityCubeText(size: 4), named: "Look.cube", in: tempDirectory)
        let identity = try CubeLUT(url: path)
        let document = EditDocument(lut: LUTSettings(lutID: identity.lutID, intensity: 1))
        let first = try Pixels.bytes(of: try await render(engine, document, lut: identity))

        // Same path, different contents — so the same LUTID, which is the whole hazard.
        try CubeLUT.write(
            cube: TestImages.toBlackCube(size: 4), size: 4, title: "Look", to: path
        )
        let replaced = try CubeLUT(url: path)
        XCTAssertEqual(replaced.lutID, identity.lutID, "precondition: the identity did not change")

        await engine.invalidateLUTCache()
        let second = try Pixels.bytes(of: try await render(engine, document, lut: replaced))

        assertPixelsDiffer(first, second,
                           "after a flush the replaced cube must reach the screen")
    }

    // MARK: - Actor isolation

    /// The cache is a mutable reference type living inside the actor. If it ever escaped — or if the
    /// engine stopped serializing — concurrent renders would race on the filter's `inputImage`.
    ///
    /// Twenty concurrent renders of the same document must all produce the same correct pixels, and
    /// must still have built exactly one filter. Each task rasterizes to bytes *before* returning, so
    /// the non-`Sendable` `CGImage` never leaves the task that received it.
    func testConcurrentRendersAreSerializedAndCorrect() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(
            adjustments: [.exposure(ev: 0.2)],
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.6)
        )
        let expected = try Pixels.bytes(of: try await render(engine, document, lut: lut))

        let source = self.source!
        let results: [[UInt8]] = await withTaskGroup(of: [UInt8]?.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    guard let cg = await engine.makeCGImage(
                        source: source, document: document, lut: lut, scale: .full, space: .current
                    ) else { return nil }
                    return try? Pixels.bytes(of: cg)
                }
            }
            var collected: [[UInt8]] = []
            for await result in group {
                if let result { collected.append(result) }
            }
            return collected
        }

        XCTAssertEqual(results.count, 20, "every concurrent render should have produced an image")
        for (index, bytes) in results.enumerated() {
            assertPixelsEqual(bytes, expected, "concurrent render \(index) diverged")
        }
        let filterCount = await engine.cachedFilterCount
        XCTAssertEqual(filterCount, 1, "concurrent renders should still share one cached filter")
    }

    // MARK: - The protocol is a real injection point

    /// Step 4's other deliverable. Once the view model renders through `RenderEngining`, its tests
    /// should not need a GPU — so the protocol has to be conformable by something trivial and usable
    /// both generically and as an existential.
    func testAFakeCanStandInForTheEngine() async throws {
        let fake = FakeRenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 0.25))

        // Generic position …
        func renderThrough(_ engine: some RenderEngining) async -> CGImage? {
            await engine.makeCGImage(
                source: ImageSource(url: URL(fileURLWithPath: "/nowhere.png"), nativeExtent: .zero),
                document: document, lut: lut,
                scale: .preview(maxSize: CGSize(width: 64, height: 64)), space: .displayP3
            )
        }
        let image = await renderThrough(fake)
        XCTAssertNotNil(image, "the fake should answer without touching a file or the GPU")

        // … and as an existential, which is what a stored `var engine: any RenderEngining` needs.
        let boxed: any RenderEngining = fake
        _ = try await boxed.encode(
            source: ImageSource(url: URL(fileURLWithPath: "/nowhere.png"), nativeExtent: .zero),
            document: document, lut: lut, scale: .full,
            format: .jpeg, quality: 0.9, space: .sRGB
        )

        // And it recorded what was asked for — the reason a fake beats a stub.
        let previews = await fake.previewRequests
        let encodes = await fake.encodeRequests
        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews.first?.document, document)
        XCTAssertEqual(previews.first?.lutID, lut.lutID)
        XCTAssertEqual(previews.first?.scale, .preview(maxSize: CGSize(width: 64, height: 64)))
        XCTAssertEqual(previews.first?.space, .displayP3)
        XCTAssertEqual(encodes.count, 1)
        XCTAssertEqual(encodes.first?.format, .jpeg)
    }

    func testTheFakeCanSimulateAnEncodeFailure() async throws {
        let fake = FakeRenderEngine()
        await fake.setShouldFailEncode(true)

        do {
            _ = try await fake.encode(
                source: ImageSource(url: URL(fileURLWithPath: "/nowhere.png"), nativeExtent: .zero),
                document: EditDocument(), lut: nil, scale: .full,
                format: .png, quality: 1, space: .sRGB
            )
            XCTFail("the fake should have thrown")
        } catch {
            guard case ImageError.exportFailed = error else {
                return XCTFail("expected exportFailed, got \(error)")
            }
        }
    }

    // MARK: - Old path still stands

    /// Step 4 ships the engine *alongside* `ImageProcessor`; the app still renders through the old
    /// path until Steps 5–7. Both must therefore still work, and — since they now share a pipeline
    /// definition of "the identity" — agree on an unedited image.
    func testTheOldPathStillWorksAndAgreesOnAnUneditedImage() async throws {
        let engine = RenderEngine()

        let viaEngine = try await render(engine, EditDocument())
        let viaProcessor = try ImageDecoder.load(from: sourceURL)
        let oldRaster = try Pixels.bytes(of: viaProcessor)

        assertPixelsEqual(try Pixels.bytes(of: viaEngine), oldRaster,
                          "the new engine and the old loader should agree on an unedited image")
    }

    // MARK: - Interactive RAW session (LUMO-070)

    /// `InteractiveRAWFilterSession` reuses one mutable `CIRAWFilter` across ticks and restores a
    /// captured baseline before applying each tick's `RAWDevelopSettings`, precisely so a value one
    /// tick pushed onto the filter cannot survive into the next tick's `nil` (decoder-default). That
    /// restore-then-apply order is the whole correctness argument for reusing the filter at all — and
    /// nothing exercised it, since real-RAW tests are opt-in and every other interactive test in this
    /// file uses a standard image, which never reaches the session.
    ///
    /// Skipped wherever there is no RAW to hand, which includes CI. See `Fixtures.localRAWURL`.
    func testInteractiveSessionDoesNotLeakSettingsAcrossTicks() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }
        let rawSource = ImageSource(url: rawURL, nativeExtent: CGSize(width: 4000, height: 3000))
        let box = CGSize(width: 256, height: 256)

        func interactiveRequest(_ settings: RAWDevelopSettings) -> RenderRequest {
            RenderRequest(
                source: rawSource, document: EditDocument(rawDevelop: settings),
                targetSize: box, quality: .interactive
            )
        }

        let engine = RenderEngine()

        // First tick: an extreme exposure push, establishing the session and writing a
        // non-default value onto the shared filter.
        let pushedImage = await engine.makeCGImage(interactiveRequest(RAWDevelopSettings(exposure: 4)))
        let pushed = try XCTUnwrap(pushedImage)
        // Second tick, same session: back to neutral. If `exposure` were not restored first, the
        // filter would still carry the +4 EV push from the tick above.
        let backToNeutralImage = await engine.makeCGImage(interactiveRequest(.neutral))
        let backToNeutral = try XCTUnwrap(backToNeutralImage)

        // A fresh engine has no session to leak from, so its neutral render is the ground truth
        // for what an uncontaminated neutral tick must look like.
        let independentEngine = RenderEngine()
        let referenceImage = await independentEngine.makeCGImage(interactiveRequest(.neutral))
        let reference = try XCTUnwrap(referenceImage)

        assertPixelsEqual(
            try Pixels.bytes(of: backToNeutral), try Pixels.bytes(of: reference), tolerance: 2,
            "a neutral tick after an exposure push must not inherit the previous tick's exposure"
        )
        assertPixelsDiffer(
            try Pixels.bytes(of: pushed), try Pixels.bytes(of: backToNeutral),
            "precondition: the exposure push must actually have changed the pushed frame"
        )

        let work = await engine.workStatistics()
        XCTAssertEqual(work.rawFilterConstructions, 1)
        XCTAssertEqual(work.rawOutputRequests, 2)
        XCTAssertEqual(work.rawPropertyWrites, 2,
                       "the exposure write and its optional reset should be the only decoder writes")
    }

    func testInteractiveRAWDownstreamEditsReuseTheCompletedOutput() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }
        let rawSource = ImageSource(url: rawURL, nativeExtent: CGSize(width: 4000, height: 3000))
        let settings = RAWDevelopSettings(exposure: 0.5)
        let engine = RenderEngine()
        func request(grainAmount: Double) -> RenderRequest {
            RenderRequest(
                source: rawSource,
                document: EditDocument(
                    rawDevelop: settings,
                    effects: EffectsAdjustments(grain: GrainAdjustments(amount: grainAmount))
                ),
                targetSize: CGSize(width: 256, height: 256), quality: .interactive
            )
        }

        _ = await engine.makeCGImage(request(grainAmount: 10))
        _ = await engine.makeCGImage(request(grainAmount: 80))

        let work = await engine.workStatistics()
        XCTAssertEqual(work.rawFilterConstructions, 1)
        XCTAssertEqual(work.rawOutputRequests, 1,
                       "a grain-only interactive edit must reuse the developed RAW output")
        XCTAssertEqual(work.rawPropertyWrites, 1)
    }
}
