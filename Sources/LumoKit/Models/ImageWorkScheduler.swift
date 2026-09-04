import Foundation

/// Schedules work that competes for the user's attention.
///
/// The scheduler owns policy, not the work itself. Editor work has its own lane and can therefore
/// start while thumbnail workers are busy. Thumbnail work is deliberately capped and its pending
/// queue is bounded; a fast folder scan cannot allocate one task per file and leave stale work
/// waiting behind the current photo.
@MainActor
final class ImageWorkScheduler {

    enum Priority: Int, CaseIterable, Sendable {
        case activeEditor = 0
        case comparison = 1
        case histogram = 2
        case adjacentFilmstrip = 3
        case visibleGrid = 4
        case background = 5
    }

    enum Lane: Sendable {
        case editor
        case thumbnail
    }

    /// The single terminal notification delivered for an admitted job.
    ///
    /// A job can leave the scheduler without its operation ever running (for example when a newer
    /// thumbnail evicts it). Callers that bridge a job to a continuation must be told about those
    /// paths as well as normal execution, otherwise the continuation can remain suspended forever.
    enum TerminalOutcome: Sendable, Equatable {
        case completed
        case cancelled
        case evicted
        case rejected
    }

    struct JobID: Hashable, Sendable {
        let rawValue: String

        init(_ rawValue: String) {
            self.rawValue = rawValue
        }
    }

    struct Configuration: Sendable, Equatable {
        var maxConcurrentThumbnails: Int = 4
        var maxQueuedThumbnails: Int = 24
        /// RenderEngine is actor-serialized. Keep only a small support backlog behind the newest
        /// visible request so inspector churn cannot accumulate actor messages.
        var maxQueuedEditorJobs: Int = 4

        static let `default` = Configuration()
    }

    typealias Operation = @MainActor @Sendable () async -> Void
    typealias TerminalHandler = @MainActor @Sendable (TerminalOutcome) -> Void

    private struct Job {
        let id: JobID
        let lane: Lane
        var priority: Priority
        let sequence: UInt64
        let operation: Operation
        let onTerminal: TerminalHandler
    }

    private struct Running {
        let lane: Lane
        let token: UInt64
        let task: Task<Void, Never>
        let onTerminal: TerminalHandler
    }

    private let configuration: Configuration
    private var queued: [JobID: Job] = [:]
    private var running: [JobID: Running] = [:]
    private var nextSequence: UInt64 = 0
    private var nextToken: UInt64 = 0

    private(set) var droppedThumbnailCount = 0
    private(set) var cancelledCount = 0
    private(set) var peakQueuedThumbnailCount = 0

    init(configuration: Configuration = .default) {
        self.configuration = Configuration(
            maxConcurrentThumbnails: max(0, configuration.maxConcurrentThumbnails),
            maxQueuedThumbnails: max(0, configuration.maxQueuedThumbnails),
            maxQueuedEditorJobs: max(0, configuration.maxQueuedEditorJobs)
        )
    }

    var pendingCount: Int { queued.count }

    var pendingThumbnailCount: Int {
        queued.values.filter { $0.lane == .thumbnail }.count
    }

    var pendingEditorCount: Int {
        queued.values.filter { $0.lane == .editor }.count
    }

    var runningCount: Int { running.count }

    var runningThumbnailCount: Int {
        running.values.filter { $0.lane == .thumbnail }.count
    }

    var canQueueThumbnail: Bool {
        runningThumbnailCount < configuration.maxConcurrentThumbnails
            || pendingThumbnailCount < configuration.maxQueuedThumbnails
    }

    var isIdle: Bool { queued.isEmpty && running.isEmpty }

    /// Add or replace a job. Replacing a running job cancels it before the new value is admitted.
    @discardableResult
    func enqueue(
        id: JobID,
        lane: Lane,
        priority: Priority,
        onTerminal: @escaping TerminalHandler = { _ in },
        operation: @escaping Operation
    ) -> Bool {
        cancel(id: id, countAsCancellation: false)

        nextSequence &+= 1
        let job = Job(
            id: id, lane: lane, priority: priority, sequence: nextSequence, operation: operation,
            onTerminal: onTerminal
        )

        if lane == .thumbnail {
            guard configuration.maxConcurrentThumbnails > 0 else {
                droppedThumbnailCount += 1
                onTerminal(.rejected)
                return false
            }
            guard
                configuration.maxQueuedThumbnails > 0
                    || runningThumbnailCount < configuration.maxConcurrentThumbnails
            else {
                droppedThumbnailCount += 1
                onTerminal(.rejected)
                return false
            }
            guard admitThumbnail(job) else {
                onTerminal(.rejected)
                return false
            }
        } else {
            guard admitEditor(job) else {
                onTerminal(.rejected)
                return false
            }
        }
        let admitted = queued[job.id] != nil
        updatePeakQueue()
        pump()
        return admitted || running[job.id] != nil
    }

    /// Change a queued job's priority without restarting it. Running work is left alone when it is
    /// still useful; callers can use `cancel` for work that has scrolled out of relevance.
    func updatePriority(for id: JobID, to priority: Priority) {
        guard var job = queued[id] else { return }
        job.priority = priority
        queued[id] = job
        pump()
    }

    func contains(_ id: JobID) -> Bool {
        queued[id] != nil || running[id] != nil
    }

    func cancel(id: JobID) {
        cancel(id: id, countAsCancellation: true)
        pump()
    }

    /// Remove a job without immediately starting another queued operation. This lets a caller
    /// replace support work and enqueue a visible edit as one admission decision.
    func cancel(id: JobID, pump: Bool) {
        cancel(id: id, countAsCancellation: true)
        if pump { self.pump() }
    }

    func cancel(ids: Set<JobID>) {
        for id in ids {
            cancel(id: id, countAsCancellation: true)
        }
        pump()
    }

    func cancelAll() {
        let ids = Set(queued.keys).union(running.keys)
        cancel(ids: ids)
    }

    private func cancel(id: JobID, countAsCancellation: Bool) {
        if let job = queued.removeValue(forKey: id) {
            if countAsCancellation { cancelledCount += 1 }
            job.onTerminal(.cancelled)
            return
        }
        if let active = running.removeValue(forKey: id) {
            active.task.cancel()
            if countAsCancellation { cancelledCount += 1 }
            active.onTerminal(.cancelled)
        }
    }

    private func admitThumbnail(_ job: Job) -> Bool {
        let pending = queued.values.filter { $0.lane == .thumbnail }
        // `pending` is only empty here when `maxQueuedThumbnails == 0` — the caller already
        // confirmed there is running capacity in that case, so there is nothing to evict and the
        // job should be queued (transiently) for `pump()` to pick straight up.
        if pending.count >= configuration.maxQueuedThumbnails,
            let worst = pending.max(by: { precedes($0, $1) })
        {
            guard precedes(job, worst) else {
                droppedThumbnailCount += 1
                return false
            }
            queued.removeValue(forKey: worst.id)
            droppedThumbnailCount += 1
            worst.onTerminal(.evicted)
        }
        queued[job.id] = job
        return true
    }

    private(set) var droppedEditorCount = 0

    private var runningEditorCount: Int {
        running.values.filter { $0.lane == .editor }.count
    }

    private func admitEditor(_ job: Job) -> Bool {
        // Once a visible edit arrives, queued histogram/comparison/prefetch work is obsolete. It
        // will be re-admitted after the frame is presented if it is still relevant.
        if job.priority == .activeEditor {
            let supportIDs = queued.values
                .filter { $0.lane == .editor && $0.priority != .activeEditor }
                .map(\.id)
            for id in supportIDs {
                guard let support = queued.removeValue(forKey: id) else { continue }
                droppedEditorCount += 1
                support.onTerminal(.evicted)
            }
        }

        guard configuration.maxQueuedEditorJobs > 0 || runningEditorCount == 0 else {
            droppedEditorCount += 1
            return false
        }
        let pending = queued.values.filter { $0.lane == .editor }
        if pending.count >= configuration.maxQueuedEditorJobs,
            let worst = pending.max(by: { precedes($0, $1) })
        {
            guard precedes(job, worst) else {
                droppedEditorCount += 1
                return false
            }
            queued.removeValue(forKey: worst.id)
            droppedEditorCount += 1
            worst.onTerminal(.evicted)
        }
        queued[job.id] = job
        return true
    }

    private func pump() {
        while let next = nextAdmissibleJob() {
            queued.removeValue(forKey: next.id)
            nextToken &+= 1
            let token = nextToken
            let task = Task { @MainActor [weak self, operation = next.operation] in
                guard !Task.isCancelled else {
                    self?.finished(id: next.id, token: token, outcome: .cancelled)
                    return
                }
                await operation()
                self?.finished(id: next.id, token: token, outcome: .completed)
            }
            running[next.id] = Running(
                lane: next.lane, token: token, task: task, onTerminal: next.onTerminal
            )
        }
    }

    private func nextAdmissibleJob() -> Job? {
        queued.values
            .filter { job in
                switch job.lane {
                case .editor:
                    return !running.values.contains(where: { $0.lane == .editor })
                case .thumbnail:
                    return runningThumbnailCount < configuration.maxConcurrentThumbnails
                }
            }
            .min(by: precedes)
    }

    private func precedes(_ lhs: Job, _ rhs: Job) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority.rawValue < rhs.priority.rawValue }
        return lhs.sequence < rhs.sequence
    }

    private func updatePeakQueue() {
        peakQueuedThumbnailCount = max(peakQueuedThumbnailCount, pendingThumbnailCount)
    }

    private func finished(id: JobID, token: UInt64, outcome: TerminalOutcome) {
        guard running[id]?.token == token else { return }
        let active = running.removeValue(forKey: id)
        active?.onTerminal(outcome)
        pump()
    }
}
