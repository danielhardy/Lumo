import Foundation
import CoreImage
import CoreGraphics
@testable import LUTzyKit

/// A `RenderEngining` that never touches the GPU.
///
/// This is the deliverable of Step 4 that is easy to overlook: once the view model renders through
/// the protocol (Step 5), its tests should be able to assert *what was asked for* — which document,
/// which scale, how many times — without a Metal device and without comparing pixels. That is only
/// possible if the protocol is genuinely conformable by something trivial, which is what this proves.
///
/// An `actor` for the same reason the real one is: the protocol is `Sendable`, and recording calls is
/// mutable state.
actor FakeRenderEngine: RenderEngining {

    /// Every `makeCGImage` call, in order.
    private(set) var previewRequests: [Request] = []
    /// Every `encode` call, in order.
    private(set) var encodeRequests: [Request] = []
    /// Every `histogram` call, in order.
    private(set) var histogramRequests: [Request] = []

    struct Request: Equatable {
        let document: EditDocument
        let lutID: LUTID?
        let scale: RenderScale
        let space: WorkingSpace
        let format: ExportFormat?
        /// The `ImageSource` the call named. Recorded so a test can tell *which* image was asked
        /// for — a batch export issues one request per file and they differ only here.
        var source: ImageSource?
    }

    /// Swap in a failure to exercise the caller's error path.
    var shouldFailEncode = false
    var previewResult: CGImage?

    init(previewResult: CGImage? = FakeRenderEngine.solidImage()) {
        self.previewResult = previewResult
    }

    func makeCGImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace
    ) -> sending CGImage? {
        previewRequests.append(Request(
            document: document, lutID: lut?.lutID, scale: scale, space: space, format: nil,
            source: source
        ))
        // Rebuilt per call rather than handing out the stored one: the result is `sending`, so it has
        // to be an image nothing else holds a reference to.
        return Self.solidImage()
    }

    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        format: ExportFormat,
        quality: CGFloat,
        space: WorkingSpace
    ) throws -> Data {
        encodeRequests.append(Request(
            document: document, lutID: lut?.lutID, scale: scale, space: space, format: format,
            source: source
        ))
        if shouldFailEncode { throw ImageError.exportFailed }
        return Data("fake-\(format.rawValue)".utf8)
    }

    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        maxDimension: Int
    ) -> HistogramData? {
        histogramRequests.append(Request(
            document: document, lutID: lut?.lutID, scale: scale, space: space, format: nil,
            source: source
        ))
        // A recognisable tally rather than `nil`: a caller that drops the result would otherwise be
        // indistinguishable from one that publishes it.
        var bins = [Int](repeating: 0, count: 256)
        bins[128] = 1
        return HistogramData(red: bins, green: bins, blue: bins, luma: bins)
    }

    /// How many times the app asked for the cube-filter cache to be dropped.
    ///
    /// A count rather than a flag: the interesting failures are "never" and "on every render", and a
    /// Bool cannot tell those apart from "once, when the library was rescanned".
    private(set) var invalidateCount = 0

    func invalidateLUTCache() { invalidateCount += 1 }

    /// How many times the app asked for capabilities. The probe costs ~25 ms, so "once per image
    /// open" is a requirement, not a detail — a count is the only way to see it.
    private(set) var capabilityProbeCount = 0

    /// What the fake reports. `nil` models a standard image.
    var stubbedCapabilities: RAWCapabilities? = .everythingSupported

    func rawCapabilities(for source: ImageSource) -> RAWCapabilities? {
        capabilityProbeCount += 1
        return stubbedCapabilities
    }

    func setStubbedCapabilities(_ value: RAWCapabilities?) { stubbedCapabilities = value }

    func setShouldFailEncode(_ value: Bool) { shouldFailEncode = value }

    /// A 2×2 opaque image — enough to be a real `CGImage`, cheap enough to make per call.
    static func solidImage() -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return ctx.makeImage()
    }
}
