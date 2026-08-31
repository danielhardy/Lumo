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
        let scheduler = ImageWorkScheduler(configuration: .init(
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
        let scheduler = ImageWorkScheduler(configuration: .init(
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
        let scheduler = ImageWorkScheduler(configuration: .init(
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
