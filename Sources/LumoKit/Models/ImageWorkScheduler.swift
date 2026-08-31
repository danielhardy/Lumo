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
        case adjacentFilmstrip = 1
        case visibleGrid = 2
        case background = 3
    }

    enum Lane: Sendable {
        case editor
        case thumbnail
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

        static let `default` = Configuration()
    }

    typealias Operation = @MainActor @Sendable () async -> Void

    private struct Job {
        let id: JobID
        let lane: Lane
        var priority: Priority
        let sequence: UInt64
        let operation: Operation
    }

    private struct Running {
        let lane: Lane
        let token: UInt64
        let task: Task<Void, Never>
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
            maxQueuedThumbnails: max(0, configuration.maxQueuedThumbnails)
        )
    }

    var pendingCount: Int { queued.count }

    var pendingThumbnailCount: Int {
        queued.values.filter { $0.lane == .thumbnail }.count
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
    func enqueue(
        id: JobID,
        lane: Lane,
        priority: Priority,
        operation: @escaping Operation
    ) {
        cancel(id: id, countAsCancellation: false)

        nextSequence &+= 1
        let job = Job(
            id: id, lane: lane, priority: priority, sequence: nextSequence, operation: operation
        )

        if lane == .thumbnail {
            guard configuration.maxConcurrentThumbnails > 0 else {
                droppedThumbnailCount += 1
                return
            }
            guard configuration.maxQueuedThumbnails > 0 || runningThumbnailCount < configuration.maxConcurrentThumbnails else {
                droppedThumbnailCount += 1
                return
            }
            admitThumbnail(job)
        } else {
            queued[id] = job
        }
        updatePeakQueue()
        pump()
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
        if queued.removeValue(forKey: id) != nil {
            if countAsCancellation { cancelledCount += 1 }
            return
        }
        if let active = running.removeValue(forKey: id) {
            active.task.cancel()
            if countAsCancellation { cancelledCount += 1 }
        }
    }

    private func admitThumbnail(_ job: Job) {
        let pending = queued.values.filter { $0.lane == .thumbnail }
        if pending.count >= configuration.maxQueuedThumbnails {
            guard let worst = pending.max(by: { precedes($0, $1) }) else { return }
            guard precedes(job, worst) else {
                droppedThumbnailCount += 1
                return
            }
            queued.removeValue(forKey: worst.id)
            droppedThumbnailCount += 1
        }
        queued[job.id] = job
    }

    private func pump() {
        while let next = nextAdmissibleJob() {
            queued.removeValue(forKey: next.id)
            nextToken &+= 1
            let token = nextToken
            let task = Task { @MainActor [weak self, operation = next.operation] in
                await operation()
                self?.finished(id: next.id, token: token)
            }
            running[next.id] = Running(lane: next.lane, token: token, task: task)
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

    private func finished(id: JobID, token: UInt64) {
        guard running[id]?.token == token else { return }
        running.removeValue(forKey: id)
        pump()
    }
}
