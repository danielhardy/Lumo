import Foundation
import CoreGraphics
import ImageIO

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
        let result: RenderResult
        let image: CGImage?
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
    private var latestRequest: RenderRequest?
    private var latestToken: Token?
    private var nextRevision: UInt64 = 0
    private var isInteracting = false

    var onPublication: PublicationHandler?
    var onFailure: FailureHandler?

    init(
        engine: any RenderEngining,
        interactiveDelay: Duration = .milliseconds(16),
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
        nextRevision &+= 1
        let token = Token(source: request.source, revision: nextRevision)
        latestRequest = request
        latestToken = token

        interactiveTask?.cancel()
        interactiveTask = nil
        settleTask?.cancel()
        settleTask = nil

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
        nextRevision &+= 1
        latestRequest = nil
        latestToken = nil
        interactiveTask?.cancel()
        interactiveTask = nil
        settleTask?.cancel()
        settleTask = nil
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
        scheduleSettled(Self.request(request, quality: .preview), token: token)
    }

    private func scheduleInteractive(_ request: RenderRequest, token: Token) {
        let delay = interactiveDelay
        interactiveTask = Task { [weak self, engine] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.render(request, token: token, phase: .interactive, engine: engine)
        }
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
        do {
            let result = try await engine.render(request)
            guard !Task.isCancelled else { return }

            // RenderResult deliberately carries Sendable bytes. ImageIO decode is still work, so it
            // is detached from the main actor before NSImage/UI state is touched by the handler.
            let image = await Task.detached {
                PreviewImageDecoder.decode(result.data)
            }.value

            guard !Task.isCancelled, isCurrent(token) else { return }
            onPublication?(Publication(
                request: request, result: result, image: image,
                revision: token.revision, phase: phase
            ))
        } catch is CancellationError {
            // Superseded interactive work is expected and intentionally silent.
        } catch {
            guard !Task.isCancelled, isCurrent(token) else { return }
            onFailure?(request)
        }
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
            output: .raster,
            space: request.space
        )
    }
}

/// Decode display bytes away from the main actor. The result is consumed immediately by a
/// main-actor publication handler and is never retained as app state across actor boundaries.
enum PreviewImageDecoder {
    nonisolated static func decode(_ data: Data) -> sending CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
