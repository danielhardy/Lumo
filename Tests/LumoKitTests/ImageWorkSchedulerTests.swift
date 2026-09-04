import XCTest

@testable import LumoKit

@MainActor
final class ImageWorkSchedulerTests: XCTestCase {

    private actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { waiters.append($0) }
        }

        func releaseAll() {
            let parked = waiters
            waiters.removeAll()
            for waiter in parked { waiter.resume() }
        }
    }

    func testActiveEditorStartsAheadOfQueuedBackgroundThumbnails() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 4
            ))
        let gate = Gate()
        var started: [String] = []

        scheduler.enqueue(id: .init("thumb-1"), lane: .thumbnail, priority: .background) {
            started.append("thumb-1")
            await gate.wait()
        }
        try await waitUntil("the first thumbnail to start") { started == ["thumb-1"] }

        scheduler.enqueue(id: .init("thumb-2"), lane: .thumbnail, priority: .background) {
            started.append("thumb-2")
        }
        scheduler.enqueue(id: .init("editor"), lane: .editor, priority: .activeEditor) {
            started.append("editor")
        }

        try await waitUntil("the editor to start") { started.contains("editor") }
        XCTAssertEqual(started.prefix(2), ["thumb-1", "editor"])

        await gate.releaseAll()
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
    }

    func testQueuedThumbnailCanBeCancelledBeforeItStarts() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 4
            ))
        let gate = Gate()
        var started: [String] = []

        scheduler.enqueue(id: .init("running"), lane: .thumbnail, priority: .background) {
            started.append("running")
            await gate.wait()
        }
        try await waitUntil("the running thumbnail") { started == ["running"] }

        scheduler.enqueue(id: .init("obsolete"), lane: .thumbnail, priority: .background) {
            started.append("obsolete")
        }
        scheduler.cancel(id: .init("obsolete"))
        await gate.releaseAll()

        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
        XCTAssertEqual(started, ["running"])
        XCTAssertGreaterThanOrEqual(scheduler.cancelledCount, 1)
    }

    func testThumbnailQueueIsBoundedAndRetainsHigherPriorityWork() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 2
            ))
        let gate = Gate()
        var started: [String] = []

        scheduler.enqueue(id: .init("running"), lane: .thumbnail, priority: .background) {
            started.append("running")
            await gate.wait()
        }
        try await waitUntil("the running thumbnail") { started == ["running"] }

        scheduler.enqueue(id: .init("background-a"), lane: .thumbnail, priority: .background) {
            started.append("background-a")
        }
        scheduler.enqueue(id: .init("background-b"), lane: .thumbnail, priority: .background) {
            started.append("background-b")
        }
        scheduler.enqueue(id: .init("adjacent"), lane: .thumbnail, priority: .adjacentFilmstrip) {
            started.append("adjacent")
        }

        XCTAssertEqual(scheduler.pendingThumbnailCount, 2)
        XCTAssertLessThanOrEqual(scheduler.peakQueuedThumbnailCount, 2)
        XCTAssertGreaterThanOrEqual(scheduler.droppedThumbnailCount, 1)

        await gate.releaseAll()
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
        XCTAssertEqual(started, ["running", "adjacent", "background-a"])
    }

    func testQueueEvictionCompletesTheEvictedJobExactlyOnce() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 1
            ))
        let gate = Gate()
        var started = false
        var outcomes: [String: [ImageWorkScheduler.TerminalOutcome]] = [:]
        let record: @MainActor (String, ImageWorkScheduler.TerminalOutcome) -> Void = {
            id, outcome in outcomes[id, default: []].append(outcome)
        }

        scheduler.enqueue(id: .init("running"), lane: .thumbnail, priority: .background) {
            started = true
            await gate.wait()
        }
        try await waitUntil("the running thumbnail") { started }

        scheduler.enqueue(
            id: .init("evicted"), lane: .thumbnail, priority: .background,
            onTerminal: { record("evicted", $0) }, operation: {}
        )
        scheduler.enqueue(
            id: .init("replacement"), lane: .thumbnail, priority: .adjacentFilmstrip,
            onTerminal: { record("replacement", $0) }, operation: {}
        )

        XCTAssertEqual(outcomes["evicted"], [.evicted])
        XCTAssertTrue(outcomes["replacement", default: []].isEmpty)
        await gate.releaseAll()
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
        XCTAssertEqual(outcomes["replacement"], [.completed])
    }

    func testCancelAllCompletesQueuedAndRunningJobsExactlyOnce() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 2
            ))
        let gate = Gate()
        var outcomes: [String: [ImageWorkScheduler.TerminalOutcome]] = [:]
        func record(_ id: String, _ outcome: ImageWorkScheduler.TerminalOutcome) {
            outcomes[id, default: []].append(outcome)
        }

        scheduler.enqueue(
            id: .init("running"), lane: .thumbnail, priority: .background,
            onTerminal: { record("running", $0) }, operation: { await gate.wait() }
        )
        try await waitUntil("the running thumbnail") { scheduler.runningThumbnailCount == 1 }
        scheduler.enqueue(
            id: .init("queued"), lane: .thumbnail, priority: .background,
            onTerminal: { record("queued", $0) }, operation: {}
        )

        scheduler.cancelAll()
        XCTAssertEqual(outcomes["running"], [.cancelled])
        XCTAssertEqual(outcomes["queued"], [.cancelled])
        XCTAssertEqual(scheduler.runningCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        await gate.releaseAll()
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(outcomes["running"], [.cancelled])
    }

    func testRejectedJobReportsItsTerminalOutcome() {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 0, maxQueuedThumbnails: 0
            ))
        var outcomes: [ImageWorkScheduler.TerminalOutcome] = []

        let admitted = scheduler.enqueue(
            id: .init("rejected"), lane: .thumbnail, priority: .visibleGrid,
            onTerminal: { outcomes.append($0) }, operation: {}
        )

        XCTAssertFalse(admitted)
        XCTAssertEqual(outcomes, [.rejected])
    }

    func testSuccessfulJobReportsCompletion() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 1
            ))
        var outcomes: [ImageWorkScheduler.TerminalOutcome] = []

        scheduler.enqueue(
            id: .init("success"), lane: .thumbnail, priority: .visibleGrid,
            onTerminal: { outcomes.append($0) }, operation: {}
        )

        try await waitUntil("the successful job") { scheduler.isIdle }
        XCTAssertEqual(outcomes, [.completed])
    }

    func testThumbnailRunsImmediatelyWhenTheQueueIsDisabled() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 2, maxQueuedThumbnails: 0
            ))
        var started: [String] = []

        scheduler.enqueue(id: .init("thumb"), lane: .thumbnail, priority: .background) {
            started.append("thumb")
        }

        try await waitUntil("the thumbnail to run despite no queue capacity") {
            started == ["thumb"]
        }
        XCTAssertEqual(scheduler.droppedThumbnailCount, 0)
    }

    func testVisibleEditorDropsQueuedSupportBeforeItIsAdmitted() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 4, maxQueuedEditorJobs: 2
            ))
        let gate = Gate()
        var started: [String] = []

        scheduler.enqueue(id: .init("support-running"), lane: .editor, priority: .histogram) {
            started.append("support-running")
            await gate.wait()
        }
        try await waitUntil("the support job to start") { started == ["support-running"] }

        scheduler.enqueue(id: .init("comparison"), lane: .editor, priority: .comparison) {
            started.append("comparison")
        }
        scheduler.enqueue(id: .init("visible"), lane: .editor, priority: .activeEditor) {
            started.append("visible")
        }

        XCTAssertEqual(scheduler.pendingEditorCount, 1)
        XCTAssertGreaterThanOrEqual(scheduler.droppedEditorCount, 1)

        await gate.releaseAll()
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
        XCTAssertEqual(started, ["support-running", "visible"])
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 2,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
