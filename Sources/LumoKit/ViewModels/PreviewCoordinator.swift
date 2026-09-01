import Foundation
import CoreGraphics
import CoreImage

/// Coordinates the display render, which has a different lifecycle from the render actor.
///
/// A slider produces a burst of edit values. During that burst the coordinator asks for a
/// viewport-sized `.interactive` result and keeps only the newest request. When the burst ends it
/// promotes that request to `.preview`, so the last interactive frame is always replaced by the
/// normal settled preview. The renderer remains an actor concerned only with executing requests;
/// this type owns cancellation, revisions, and the policy for what is allowed onto the screen.
@MainActor
final class PreviewCoordinator {

    enum Phase: Sendable, Equatable {
        case interactive
        case settled
    }

    struct Publication {
        let request: RenderRequest
        let image: CGImage?
        let gpuImage: CIImage?
        let revision: UInt64
        let phase: Phase
    }

    typealias PublicationHandler = @MainActor (Publication) -> Void
    typealias FailureHandler = @MainActor (RenderRequest) -> Void

    private struct Token: Equatable {
        let source: ImageSource
        let revision: UInt64
    }

    private let engine: any RenderEngining
    private let interactiveDelay: Duration
    private let settleDelay: Duration
    private var interactiveTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    /// True only after an interactive task has entered the renderer. A renderer actor may still be
    /// finishing a non-cancellable Core Image operation after its caller is cancelled; tracking
    /// that boundary prevents every pointer tick from becoming another actor message.
    private var interactiveRenderInFlight = false
    private var pendingInteractive: (request: RenderRequest, token: Token)?
    private var latestRequest: RenderRequest?
    private var latestToken: Token?
    private var nextRevision: UInt64 = 0
    private var isInteracting = false

    var onPublication: PublicationHandler?
    var onFailure: FailureHandler?
    let telemetry = LiveEditTelemetry()

    init(
        engine: any RenderEngining,
        interactiveDelay: Duration = .zero,
        settleDelay: Duration = .milliseconds(60)
    ) {
        self.engine = engine
        self.interactiveDelay = interactiveDelay
        self.settleDelay = settleDelay
    }

    /// Start a gesture. The coordinator will not settle until `endInteraction()` is called.
    func beginInteraction() {
        isInteracting = true
        settleTask?.cancel()
        settleTask = nil
    }

    /// End a gesture and immediately request the final preview-quality result.
    func endInteraction() {
        guard isInteracting else { return }
        isInteracting = false
        settleTask?.cancel()
        settleTask = nil
        settleLatest()
    }

    /// Submit a complete display request. The request is value state, so a caller can safely create
    /// it on the main actor and the renderer can evaluate it elsewhere.
    func submit(_ request: RenderRequest, phase: Phase = .settled) {
        let hadPendingWork = interactiveTask != nil || settleTask != nil
        if hadPendingWork {
            LumoObservability.event(.cancellation, source: request.source, quality: request.quality,
                                    detail: "superseded")
        }
        // A previous settled request is not a coalesced edit. Only count a new interactive value
        // replacing another interactive task in the same burst.
        if phase == .interactive, interactiveTask != nil {
            LumoObservability.event(.coalesced, source: request.source, quality: .interactive,
                                    detail: "interactive-burst")
        }

        nextRevision &+= 1
        let token = Token(source: request.source, revision: nextRevision)
        telemetry.input(source: request.source, request: request, revision: token.revision)
        LumoObservability.liveEdit(.pointerInput, source: request.source, quality: request.quality,
                                   revision: token.revision)
        if phase == .interactive, interactiveTask != nil { telemetry.coalesced(token.revision) }
        latestRequest = request
        latestToken = token

        interactiveTask?.cancel()
        interactiveTask = nil
        settleTask?.cancel()
        settleTask = nil
        pendingInteractive = nil

        switch phase {
        case .interactive:
            let interactiveRequest = Self.request(request, quality: .interactive)
            latestRequest = interactiveRequest
            scheduleInteractive(interactiveRequest, token: token)

            // Tests and non-Slider callers do not have editing callbacks. They still get the same
            // gesture behavior through the quiet-period fallback; an explicit interaction keeps
            // this timer from firing until the control reports that it ended.
            if !isInteracting {
                let delay = settleDelay
                settleTask = Task { [weak self] in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                    self?.settleLatest()
                }
            }

        case .settled:
            scheduleSettled(request, token: token)
        }
    }

    /// Invalidate every in-flight publication, including one for a source that happens to compare
    /// equal to the next source. This is the source-generation boundary used by navigation.
    func cancel() {
        if interactiveTask != nil || settleTask != nil {
            LumoObservability.event(.cancellation, source: latestRequest?.source,
                                    quality: latestRequest?.quality, detail: "navigation")
        }
        nextRevision &+= 1
        latestRequest = nil
        latestToken = nil
        interactiveTask?.cancel()
        interactiveTask = nil
        settleTask?.cancel()
        settleTask = nil
        pendingInteractive = nil
        isInteracting = false
    }

    private func settleLatest() {
        guard let request = latestRequest else { return }
        nextRevision &+= 1
        let token = Token(source: request.source, revision: nextRevision)
        latestToken = token
        interactiveTask?.cancel()
        interactiveTask = nil
        settleTask = nil
        pendingInteractive = nil
        scheduleSettled(Self.request(request, quality: .preview), token: token)
    }

    private func scheduleInteractive(_ request: RenderRequest, token: Token) {
        if interactiveRenderInFlight {
            // Keep only value state while the renderer finishes the one operation already in
            // flight. This is latest-wins coalescing without building an actor/task queue.
            pendingInteractive = (request, token)
            return
        }

        interactiveTask = Task { [weak self, engine] in
            // No debounce belongs before the first interactive frame. The in-flight/pending
            // state below is the frame pacer: it permits one render and retains only the latest
            // document while Core Image finishes the non-cancellable operation.
            if self?.interactiveDelay != .zero {
                try? await Task.sleep(for: self?.interactiveDelay ?? .zero)
            }
            guard !Task.isCancelled else { return }
            self?.interactiveRenderInFlight = true
            await self?.render(request, token: token, phase: .interactive, engine: engine)
            self?.interactiveRenderFinished(token: token)
        }
    }

    private func interactiveRenderFinished(token: Token) {
        guard interactiveRenderInFlight else { return }
        interactiveRenderInFlight = false

        // A settled request supersedes this work when a gesture ended, so only continue an
        // interactive burst that is still active.
        guard isInteracting, let pending = pendingInteractive else {
            pendingInteractive = nil
            return
        }
        pendingInteractive = nil
        scheduleInteractive(pending.request, token: pending.token)
    }

    private func scheduleSettled(_ request: RenderRequest, token: Token) {
        interactiveTask?.cancel()
        interactiveTask = nil
        interactiveTask = Task { [weak self, engine] in
            guard !Task.isCancelled else { return }
            await self?.render(request, token: token, phase: .settled, engine: engine)
        }
    }

    private func render(
        _ request: RenderRequest,
        token: Token,
        phase: Phase,
        engine: any RenderEngining
    ) async {
        telemetry.mark(token.revision, renderStart: LiveEditTelemetryClock.now)
        LumoObservability.liveEdit(.renderStart, source: request.source, quality: request.quality,
                                   revision: token.revision)
        let gpuImage = await engine.makeCIImage(request)
        // Test doubles and non-GPU conformers retain the old raster seam. Once a GPU image exists,
        // the persistent presentation surface owns display for both phases, so rasterizing the
        // same request would rebuild the graph and perform a redundant second render pass.
        let image = gpuImage == nil ? await engine.makeCGImage(request) : nil
        telemetry.mark(token.revision, renderEnd: LiveEditTelemetryClock.now)
        LumoObservability.liveEdit(.renderEnd, source: request.source, quality: request.quality,
                                   revision: token.revision)
        guard !Task.isCancelled else { return }
        guard isCurrent(token) else {
            let age = nextRevision >= token.revision ? nextRevision - token.revision : 0
            telemetry.stale(token.revision, age: age)
            LumoObservability.liveEdit(.staleRevision, source: request.source, quality: request.quality,
                                       revision: token.revision, detail: "age=\(age)")
            return
        }
        guard image != nil || gpuImage != nil else {
            onFailure?(request)
            return
        }
        onPublication?(Publication(
            request: request, image: image, gpuImage: gpuImage,
            revision: token.revision, phase: phase
        ))
    }

    private func isCurrent(_ token: Token) -> Bool {
        latestToken == token && latestRequest?.source == token.source
    }

    private static func request(_ request: RenderRequest, quality: RenderQuality) -> RenderRequest {
        RenderRequest(
            source: request.source,
            document: request.document,
            lut: request.lut,
            targetSize: request.targetSize,
            quality: quality,
            frameBudgetMilliseconds: request.frameBudgetMilliseconds,
            output: .raster,
            space: request.space
        )
    }
}
