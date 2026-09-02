import XCTest
import CoreGraphics
import ImageIO
@testable import LumoKit

/// Cache contract tests: cache hits are observable, keys are complete, and resource use stays
/// bounded without ever caching the final full-resolution export path.
final class RenderCacheTests: TempDirectoryTestCase {

    private func makeSource() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "cache.png", in: tempDirectory)
        return ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
    }

    private func request(
        source: ImageSource,
        document: EditDocument = EditDocument(),
        targetSize: CGSize = CGSize(width: 32, height: 32),
        quality: RenderQuality = .preview,
        space: WorkingSpace = .sRGB
    ) -> RenderRequest {
        RenderRequest(
            source: source, document: document, targetSize: targetSize,
            quality: quality, output: .raster, space: space
        )
    }

    func testIdenticalPreviewRequestsHitAndExposeCounters() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let request = request(source: source)
        let sourceKeyBefore = RenderSourceFingerprint(source)

        _ = try await engine.render(request)
        let sourceKeyAfter = RenderSourceFingerprint(source)
        _ = try await engine.render(request)

        XCTAssertEqual(sourceKeyBefore, sourceKeyAfter)
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 1)
        XCTAssertEqual(stats.preview.hits, 1)
        XCTAssertEqual(stats.preview.count, 1)
    }

    func testPreviewKeyIncludesDocumentSizeQualityAndWorkingSpace() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let document = EditDocument(adjustments: [.exposure(ev: 0.25)])

        _ = try await engine.render(request(source: source))
        _ = try await engine.render(request(source: source, document: document))
        _ = try await engine.render(request(source: source, targetSize: CGSize(width: 48, height: 48)))
        _ = try await engine.render(request(source: source, quality: .interactive))
        _ = try await engine.render(request(source: source, space: .displayP3))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 5)
        XCTAssertEqual(stats.preview.hits, 0)
    }

    func testPreviewKeyIncludesAllGrainParameters() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let neutral = request(source: source)
        let amount = request(source: source, document: EditDocument(effects: EffectsAdjustments(
            grain: GrainAdjustments(amount: 35)
        )))
        let size = request(source: source, document: EditDocument(effects: EffectsAdjustments(
            grain: GrainAdjustments(amount: 35, size: 80)
        )))
        let roughness = request(source: source, document: EditDocument(effects: EffectsAdjustments(
            grain: GrainAdjustments(amount: 35, size: 80, roughness: 15)
        )))

        _ = try await engine.render(neutral)
        _ = try await engine.render(amount)
        _ = try await engine.render(size)
        _ = try await engine.render(roughness)

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 4)
        XCTAssertEqual(stats.preview.hits, 0)
    }

    func testFullResolutionRequestsNeverEnterThePreviewCache() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let full = RenderRequest(source: source, document: EditDocument(), quality: .export, output: .raster)

        _ = try await engine.render(full)
        _ = try await engine.render(full)

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.hits, 0)
        XCTAssertEqual(stats.preview.misses, 0)
        XCTAssertEqual(stats.preview.count, 0)
    }

    func testDevelopedSourceIsReusedAcrossDifferentEdits() async throws {
        let source = try makeSource()
        let engine = RenderEngine()

        _ = try await engine.render(request(source: source))
        _ = try await engine.render(request(
            source: source, document: EditDocument(adjustments: [.vibrance(amount: 0.3)])
        ))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.developedSource.misses, 1)
        XCTAssertEqual(stats.developedSource.hits, 1)
    }

    func testDownstreamOnlyEditsReuseTheCompletedProcessingPrefix() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let firstDocument = EditDocument(
            light: LightAdjustments(exposure: 0.25),
            effects: EffectsAdjustments(texture: 20, grain: GrainAdjustments(amount: 15))
        )
        let secondDocument = EditDocument(
            light: LightAdjustments(exposure: 0.25),
            effects: EffectsAdjustments(texture: 20, grain: GrainAdjustments(amount: 65))
        )

        _ = await engine.makeCGImage(request(source: source, document: firstDocument))
        _ = await engine.makeCGImage(request(source: source, document: secondDocument))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.developedSource.misses, 1)
        XCTAssertEqual(stats.developedSource.hits, 1)
        XCTAssertEqual(stats.processingPrefix.misses, 1)
        XCTAssertEqual(stats.processingPrefix.hits, 1,
                       "grain-only edits must not rebuild the completed pre-LUT prefix")
    }

    func testCachedPrefixPreservesDownstreamCropGrainAndLUTPixels() async throws {
        let source = try makeSource()
        let lut = TestImages.warmLUT()
        let engine = RenderEngine()
        let first = EditDocument(
            light: LightAdjustments(contrast: 25),
            effects: EffectsAdjustments(
                texture: 18,
                vignette: VignetteAdjustments(amount: 30),
                grain: GrainAdjustments(amount: 15)
            ),
            crop: CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.15, width: 0.75, height: 0.7)),
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.35)
        )
        let second = EditDocument(
            light: LightAdjustments(contrast: 25),
            effects: EffectsAdjustments(
                texture: 18,
                vignette: VignetteAdjustments(amount: 30),
                grain: GrainAdjustments(amount: 70)
            ),
            crop: first.crop,
            lut: LUTSettings(lutID: lut.lutID, intensity: 0.8)
        )
        func makeRequest(_ document: EditDocument) -> RenderRequest {
            RenderRequest(
                source: source, document: document, lut: lut,
                targetSize: CGSize(width: 64, height: 64), quality: .preview
            )
        }

        _ = await engine.makeCGImage(makeRequest(first))
        let cachedImage = await engine.makeCGImage(makeRequest(second))
        let cached = try XCTUnwrap(cachedImage)
        let freshEngine = RenderEngine()
        let freshImage = await freshEngine.makeCGImage(makeRequest(second))
        let fresh = try XCTUnwrap(freshImage)

        XCTAssertEqual(cached.width, fresh.width)
        XCTAssertEqual(cached.height, fresh.height)
        assertPixelsEqual(try Pixels.bytes(of: cached), try Pixels.bytes(of: fresh), tolerance: 2,
                          "a materialized prefix must preserve downstream LUT, crop, vignette, and grain")
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.processingPrefix.hits, 1)
    }

    func testUpstreamEditsInvalidateOnlyTheProcessingPrefix() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let first = EditDocument(light: LightAdjustments(exposure: 0.25))
        let second = EditDocument(light: LightAdjustments(exposure: 0.75))

        _ = await engine.makeCGImage(request(source: source, document: first))
        _ = await engine.makeCGImage(request(source: source, document: second))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.developedSource.misses, 1)
        XCTAssertEqual(stats.developedSource.hits, 1,
                       "a Light edit must reuse the unchanged developed source")
        XCTAssertEqual(stats.processingPrefix.misses, 2)
        XCTAssertEqual(stats.processingPrefix.hits, 0)
    }

    func testFullResolutionWorkNeverEntersTheProcessingPrefixCache() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let document = EditDocument(light: LightAdjustments(exposure: 0.5))
        let request = RenderRequest(
            source: source, document: document, quality: .export,
            output: .encoded(format: .png, quality: 1)
        )

        _ = try await engine.render(request)
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.processingPrefix.count, 0)
        XCTAssertEqual(stats.processingPrefix.misses, 0)
    }

    func testProcessingPrefixEvictionHonorsItsIndependentBudget() async throws {
        let source = try makeSource()
        let engine = RenderEngine(configuration: RenderCacheConfiguration(
            previewMaxEntries: 12, previewMaxCostBytes: 10_000_000,
            developedSourceMaxEntries: 2, developedSourceMaxCostBytes: 10_000_000,
            processingPrefixMaxEntries: 1, processingPrefixMaxCostBytes: 10_000_000
        ))

        _ = await engine.makeCGImage(request(
            source: source, document: EditDocument(light: LightAdjustments(exposure: 0.1))
        ))
        _ = await engine.makeCGImage(request(
            source: source, document: EditDocument(light: LightAdjustments(exposure: 0.2))
        ))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.processingPrefix.count, 1)
        XCTAssertGreaterThanOrEqual(stats.processingPrefix.evictions, 1)
    }

    func testCacheCostAccountingCannotOverflow() {
        let cache = BoundedLRUCache<Int, Int>(maxEntries: 2, maxCostBytes: Int.max)
        cache.insert(1, for: 1, cost: Int.max)
        cache.insert(2, for: 2, cost: Int.max)

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.statistics.costBytes, Int.max)
    }

    func testEffectiveInteractiveScaleCannotReuseSettledDevelopedSource() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 3_000, height: 2_000, named: "above-cap-cache.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 3_000, height: 2_000))
        let engine = RenderEngine()
        let settled = request(source: source, targetSize: CGSize(width: 2_400, height: 1_600))
        let interactive = request(
            source: source, targetSize: CGSize(width: 2_400, height: 1_600), quality: .interactive
        )

        func extent(of image: CIImage?) -> CGSize {
            image?.extent.integral.size ?? .zero
        }

        let interactiveFirst = await engine.makeCIImage(interactive)
        let settledSecond = await engine.makeCIImage(settled)
        XCTAssertEqual(extent(of: interactiveFirst), CGSize(width: 1_500, height: 1_000))
        XCTAssertEqual(extent(of: settledSecond), CGSize(width: 2_400, height: 1_600))

        let reverseEngine = RenderEngine()
        let settledFirst = await reverseEngine.makeCIImage(settled)
        let interactiveSecond = await reverseEngine.makeCIImage(interactive)
        XCTAssertEqual(extent(of: settledFirst), CGSize(width: 2_400, height: 1_600))
        XCTAssertEqual(extent(of: interactiveSecond), CGSize(width: 1_500, height: 1_000))
    }

    func testInteractiveBudgetsWithDifferentEffectiveScalesDoNotCollide() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 3_000, height: 2_000, named: "budget-cache.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 3_000, height: 2_000))
        let engine = RenderEngine()
        let request = { (budget: Double) in
            RenderRequest(
                source: source, document: EditDocument(), targetSize: CGSize(width: 2_400, height: 1_600),
                quality: .interactive, frameBudgetMilliseconds: budget
            )
        }

        let short = await engine.makeCIImage(request(16.7))
        let generous = await engine.makeCIImage(request(33.4))
        XCTAssertEqual(short?.extent.integral.size, CGSize(width: 1_500, height: 1_000))
        XCTAssertEqual(generous?.extent.integral.size, CGSize(width: 2_122, height: 1_415))
    }

    func testSourceContentFingerprintSeparatesDataBackedImages() async throws {
        let firstURL = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "first.png", in: tempDirectory)
        let secondURL = try Fixtures.writeGradientPNG(width: 64, height: 96, named: "second.png", in: tempDirectory)
        let first = ImageSource(data: try Data(contentsOf: firstURL), nativeExtent: CGSize(width: 96, height: 64))
        let second = ImageSource(data: try Data(contentsOf: secondURL), nativeExtent: CGSize(width: 64, height: 96))
        let engine = RenderEngine()

        _ = try await engine.render(request(source: first))
        _ = try await engine.render(request(source: second))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 2)
        XCTAssertEqual(stats.preview.hits, 0)
    }

    func testReplacingAURLBackedSourceCannotReuseItsPreview() async throws {
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "mutable.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let engine = RenderEngine()
        let request = request(source: source)
        let first = try await engine.render(request)

        let replacement = try Fixtures.makeCGImage(width: 96, height: 64, red: 0.1, green: 0.8, blue: 0.2)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, replacement, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let second = try await engine.render(request)
        XCTAssertNotEqual(first.data, second.data)
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.hits, 0)
        XCTAssertEqual(stats.preview.misses, 2)
    }

    func testExplicitInvalidationForcesTheNextPreviewToMiss() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let request = request(source: source)

        _ = try await engine.render(request)
        await engine.invalidateRenderCaches()
        _ = try await engine.render(request)

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.misses, 2)
        XCTAssertEqual(stats.preview.hits, 0)
    }

    func testConfiguredLimitEvictsLeastRecentlyUsedPreviewEntries() async throws {
        let source = try makeSource()
        let engine = RenderEngine(configuration: RenderCacheConfiguration(
            previewMaxEntries: 1, previewMaxCostBytes: 1_000_000,
            developedSourceMaxEntries: 2, developedSourceMaxCostBytes: 1_000_000
        ))

        _ = try await engine.render(request(source: source, targetSize: CGSize(width: 24, height: 24)))
        _ = try await engine.render(request(source: source, targetSize: CGSize(width: 32, height: 32)))
        _ = try await engine.render(request(source: source, targetSize: CGSize(width: 24, height: 24)))

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.count, 1)
        XCTAssertGreaterThanOrEqual(stats.preview.evictions, 1)
        XCTAssertEqual(stats.preview.misses, 3)
    }

    func testMemoryPressurePurgesRenderAndThumbnailCaches() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        _ = try await engine.render(request(source: source))
        _ = Thumbnails.generate(from: sourceURL(for: source))

        await engine.evictForMemoryPressure()
        let renderStats = await engine.cacheStatistics()
        XCTAssertEqual(renderStats.preview.count, 0)
        XCTAssertGreaterThanOrEqual(renderStats.preview.evictions, 1)
        XCTAssertEqual(Thumbnails.cacheStatistics().count, 0)
    }

    func testThumbnailRequestsHitAndFileChangesMiss() throws {
        Thumbnails.invalidateCache()
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "thumb-cache.png", in: tempDirectory)
        let before = Thumbnails.cacheStatistics()

        XCTAssertNotNil(Thumbnails.generate(from: url, maxPixelSize: 40))
        XCTAssertNotNil(Thumbnails.generate(from: url, maxPixelSize: 40))
        let afterHit = Thumbnails.cacheStatistics()
        XCTAssertEqual(afterHit.hits - before.hits, 1)

        // Replacing the file changes its resource fingerprint even though its path and dimensions
        // remain the same, so the old pixels cannot be served from the thumbnail cache.
        let replacement = try Fixtures.makeCGImage(width: 96, height: 64, red: 0.1, green: 0.8, blue: 0.2)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, replacement, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertNotNil(Thumbnails.generate(from: url, maxPixelSize: 40))
        let afterChange = Thumbnails.cacheStatistics()
        XCTAssertEqual(afterChange.misses - afterHit.misses, 1)
    }

    private func sourceURL(for source: ImageSource) -> URL {
        guard case .url(let url) = source.backing else { fatalError("test source must be URL-backed") }
        return url
    }
}
