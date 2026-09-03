import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LumoKit

extension RAWCapabilities {

    /// Every gate open, and **every seed a different value that is not the field default**.
    ///
    /// `.everyGateOpen` cannot serve as the stub for seed tests: it leaves all twelve seeds at
    /// 0/false, which is exactly what a getter falling back to a hardcoded constant returns, so
    /// "the seed was read" and "a constant was guessed" are literally the same number. Every value
    /// here is distinct from every other, so a getter wired to the *wrong* seed field also fails
    /// rather than coincidentally matching its neighbour.
    ///
    /// `lensCorrectionEnabled` is deliberately `false` while every other flag is on: the getter it
    /// replaced returned a hardcoded `true`, so `false` is the only value that can catch a
    /// regression to it. Likewise the numbers below avoid 0 and 1.
    static let distinctivelySeeded = RAWCapabilities(
        isSharpnessSupported: true,
        isContrastSupported: true,
        isDetailSupported: true,
        isMoireReductionSupported: true,
        isLocalToneMapSupported: true,
        isLuminanceNoiseReductionSupported: true,
        isColorNoiseReductionSupported: true,
        isLensCorrectionSupported: true,
        isHighlightRecoverySupported: true,
        asShotTemperature: 5842.2,
        asShotTint: 14.04,
        baselineExposure: 0.37,
        shadowBias: -0.21,
        sharpnessAmount: 0.11,
        contrastAmount: 0.22,
        detailAmount: 1.33,
        moireReductionAmount: 0.44,
        localToneMapAmount: 0.55,
        luminanceNoiseReductionAmount: 0.66,
        colorNoiseReductionAmount: 0.77,
        lensCorrectionEnabled: false
    )
}

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

    /// Every request sent through the UI-independent renderer API, in order.
    private(set) var renderRequests: [RenderRequest] = []

    /// Every `makeCGImage` call, in order.
    private(set) var previewRequests: [Request] = []
    /// Every `encode` call, in order.
    private(set) var encodeRequests: [Request] = []
    /// Every `histogram` call, in order.
    private(set) var histogramRequests: [Request] = []
    /// Whether histogram calls should pause before returning. This makes cancellation and
    /// revision guards observable instead of letting a synchronous fake hide a late-result race.
    private var histogramIsGated = false
    private var parkedHistograms: [CheckedContinuation<Void, Never>] = []
    private var shouldFailHistogram = false
    private var previewIsGated = false
    private var parkedPreviews: [CheckedContinuation<Void, Never>] = []

    struct Request: Equatable {
        let document: EditDocument
        let lutID: LUTID?
        let scale: RenderScale
        let space: WorkingSpace
        let format: ExportFormat?
        /// The `ImageSource` the call named. Recorded so a test can tell *which* image was asked
        /// for — a batch export issues one request per file and they differ only here.
        var source: ImageSource?

        init(
            document: EditDocument,
            lutID: LUTID?,
            scale: RenderScale,
            space: WorkingSpace,
            format: ExportFormat?,
            source: ImageSource?
        ) {
            self.document = document
            self.lutID = lutID
            self.scale = scale
            self.space = space
            self.format = format
            self.source = source
        }

        init(request: RenderRequest) {
            document = request.document
            lutID = request.lut?.lutID
            scale = request.renderScale
            space = request.space
            switch request.output {
            case .raster:
                format = nil
            case .encoded(let format, _):
                self.format = format
            }
            source = request.source
        }
    }

    /// Swap in a failure to exercise the caller's error path.
    var shouldFailEncode = false
    /// Optional gates used by export lifecycle tests. The real engine owns one serial export lane;
    /// these counters make that bound observable without allocating full-resolution images.
    private var encodeGateAfterFirst = false
    private var parkedEncodes: [CheckedContinuation<Void, Never>] = []
    private(set) var activeEncodes = 0
    private(set) var maxConcurrentEncodes = 0
    var previewResult: CGImage?

    init(previewResult: CGImage? = FakeRenderEngine.solidImage()) {
        self.previewResult = previewResult
    }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        try Task.checkCancellation()
        renderRequests.append(request)
        let record = Request(request: request)
        switch request.output {
        case .raster:
            previewRequests.append(record)
            if previewIsGated {
                await withCheckedContinuation { parkedPreviews.append($0) }
            }
            guard let image = previewResult ?? Self.solidImage(),
                  let data = Self.pngData(for: image)
            else { throw ImageError.processingFailed }
            try Task.checkCancellation()
            return RenderResult(
                data: data, extent: CGSize(width: image.width, height: image.height),
                colorSpace: request.space, quality: request.quality, output: request.output
            )

        case .encoded(let format, _):
            encodeRequests.append(record)
            activeEncodes += 1
            maxConcurrentEncodes = max(maxConcurrentEncodes, activeEncodes)
            defer { activeEncodes -= 1 }
            if encodeGateAfterFirst, encodeRequests.count >= 2 {
                await withCheckedContinuation { parkedEncodes.append($0) }
            }
            try Task.checkCancellation()
            if shouldFailEncode { throw ImageError.exportFailed }
            return RenderResult(
                data: Data("fake-\(format.rawValue)".utf8), extent: .zero,
                colorSpace: request.space, quality: request.quality, output: request.output
            )
        }
    }

    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        maxDimension: Int
    ) async -> HistogramData? {
        histogramRequests.append(Request(
            document: document, lutID: lut?.lutID, scale: scale, space: space, format: nil,
            source: source
        ))
        if histogramIsGated {
            await withCheckedContinuation { parkedHistograms.append($0) }
        }
        if shouldFailHistogram { return nil }
        // A recognisable tally rather than `nil`: a caller that drops the result would otherwise be
        // indistinguishable from one that publishes it.
        var bins = [Int](repeating: 0, count: 256)
        let adjustmentExposure = document.adjustments.reduce(0.0) { partial, node in
            guard case .exposure(let ev) = node else { return partial }
            return partial + ev
        }
        let marker = max(
            0, min(255, Int(((document.rawDevelop.exposure ?? 0) + adjustmentExposure + 10) * 10))
        )
        bins[marker] = 1
        return HistogramData(red: bins, green: bins, blue: bins, luma: bins)
    }

    /// Hold histogram responses until the test has arranged a newer display revision.
    func gateHistogram() { histogramIsGated = true }

    func setShouldFailHistogram(_ value: Bool) { shouldFailHistogram = value }

    /// Release only the oldest parked response while leaving the gate closed. This is useful for
    /// proving that an obsolete response cannot publish over a newer request that is still running.
    func releaseNextHistogram() {
        guard !parkedHistograms.isEmpty else { return }
        parkedHistograms.removeFirst().resume()
    }

    /// Release every response currently parked in the fake. New calls proceed immediately after
    /// this point, so a test can release stale and current work together and inspect publication.
    func releaseHistograms() {
        histogramIsGated = false
        let parked = parkedHistograms
        parkedHistograms.removeAll()
        parked.forEach { $0.resume() }
    }

    /// Hold raster preview requests so comparison tests can release an obsolete baseline after a
    /// source switch and prove its generation guard rejects the late result.
    func gatePreviews() { previewIsGated = true }

    func releaseNextPreview() {
        guard !parkedPreviews.isEmpty else { return }
        parkedPreviews.removeFirst().resume()
    }

    func releasePreviews() {
        previewIsGated = false
        let parked = parkedPreviews
        parkedPreviews.removeAll()
        parked.forEach { $0.resume() }
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

    /// A controllable preparation seam for navigation tests. It stands in for a decoder operation
    /// that cannot be interrupted after it has entered the framework.
    private(set) var sourcePreparationCount = 0
    private var sourcePreparationIsGated = false
    private var parkedSourcePreparation: CheckedContinuation<Void, Never>?

    func gateSourcePreparation() { sourcePreparationIsGated = true }

    func releaseSourcePreparation() {
        sourcePreparationIsGated = false
        parkedSourcePreparation?.resume()
        parkedSourcePreparation = nil
    }

    func prepareSource(_ source: ImageSource) async -> ImageSourcePreparation? {
        sourcePreparationCount += 1
        if sourcePreparationIsGated {
            await withCheckedContinuation { parkedSourcePreparation = $0 }
        }
        if source.kind == .raw {
            // The fake has no decoder, but it still needs to model the value-state transition that
            // production performs with CIRAWFilter.nativeSize.
            let extent = source.nativeExtent == .zero
                ? CGSize(width: 4_000, height: 3_000) : source.nativeExtent
            return ImageSourcePreparation(source: ImageSource(
                backing: source.backing, kind: .raw, nativeExtent: extent
            ))
        }
        let extent: CGSize?
        switch source.backing {
        case .url(let url): extent = try? ImageDecoder.prepareStandard(from: url)
        case .data(let data): extent = try? ImageDecoder.prepareStandard(from: data, name: "fake")
        }
        guard let extent else { return nil }
        return ImageSourcePreparation(source: ImageSource(
            backing: source.backing, kind: source.kind, nativeExtent: extent
        ))
    }

    /// What the fake reports. `nil` models a standard image.
    ///
    /// Distinctively seeded rather than `.everyGateOpen`: that value leaves every seed at its
    /// field default, so a getter reading a seed and a getter returning a hardcoded constant produce
    /// the same number and no test can tell them apart. See `RAWCapabilities.distinctivelySeeded`.
    var stubbedCapabilities: RAWCapabilities? = .distinctivelySeeded

    /// Whether an incoming probe should park until `releaseProbe()` is called.
    ///
    /// **The in-flight state is a real state, and a state you cannot hold still is a state you
    /// cannot assert.** `AppViewModel.developPanelState` is `.probing` between "the image opened"
    /// and "the probe answered" — 25–170 ms in the app, and effectively zero against this fake, so a
    /// test racing it would be a flake either way it landed. Gating the probe makes that window last
    /// as long as the test needs.
    private var probeIsGated = false
    private var parkedProbe: CheckedContinuation<Void, Never>?

    func gateProbe() { probeIsGated = true }

    /// Let a parked probe finish, and stop parking new ones.
    ///
    /// Ordering note for callers: wait until `capabilityProbeCount` has moved before releasing. The
    /// count is incremented and the continuation stored in the same actor-synchronous run as the
    /// suspension, so an *external* read of the count that returns 1 can only have been serviced
    /// after this actor reached that suspension point — the continuation is therefore already
    /// stored, and `releaseProbe()` cannot no-op past a probe that has not parked yet.
    func releaseProbe() {
        probeIsGated = false
        parkedProbe?.resume()
        parkedProbe = nil
    }

    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? {
        capabilityProbeCount += 1
        if probeIsGated {
            await withCheckedContinuation { parkedProbe = $0 }
        }
        return stubbedCapabilities
    }

    func setStubbedCapabilities(_ value: RAWCapabilities?) { stubbedCapabilities = value }

    func setShouldFailEncode(_ value: Bool) { shouldFailEncode = value }

    /// Let the first encode finish but hold the second until the test chooses to release it.
    func gateEncodeAfterFirst() { encodeGateAfterFirst = true }

    func releaseEncode() {
        encodeGateAfterFirst = false
        let parked = parkedEncodes
        parkedEncodes.removeAll()
        parked.forEach { $0.resume() }
    }

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

    private static func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
