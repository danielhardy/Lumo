import Foundation

/// Main-actor orchestration for durable edit snapshots.
///
/// `EditDocumentStore` owns file I/O and actor isolation. This collaborator owns the application
/// policy around that store: coalescing edits by asset, checkpointing normal edits, serializing a
/// forced flush behind an in-flight write, and retaining failed snapshots for retry. Keeping that
/// policy here makes persistence independently testable and prevents `AppViewModel` from becoming
/// the second persistence implementation.
@MainActor
final class EditPersistenceCoordinator {
    private struct PendingSnapshot: Equatable {
        let document: EditDocument
        let reference: EditSourceReference
        let reportsStatus: Bool
        let force: Bool
    }

    private static let checkpoint: Duration = .milliseconds(250)

    let store: EditDocumentStore
    private var task: Task<PersistenceFlushResult, Never>?
    private var generation = 0
    private var pending: [PhotoAssetID: PendingSnapshot] = [:]
    private var peakPending = 0
    private var lastFailureMessage: String?

    /// Called on the main actor when a user-facing store error changes.
    var onStatusChange: ((String?) -> Void)?
    /// Called on the main actor for a failed write, without making the coordinator depend on the
    /// view model's status-bar policy.
    var onFailure: ((String) -> Void)?

    init(store: EditDocumentStore) {
        self.store = store
    }

    var pendingCount: Int { pending.count }
    var peakPendingCount: Int { peakPending }

    /// Queue the newest value for an asset. The latest snapshot wins, while a force request (used
    /// for multi-photo paste and termination) is sticky until its snapshot is durable.
    func enqueue(
        _ document: EditDocument,
        for reference: EditSourceReference,
        reportsStatus: Bool,
        force: Bool = false
    ) {
        let assetID = reference.assetID
        let prior = pending[assetID]
        pending[assetID] = PendingSnapshot(
            document: document,
            reference: reference,
            reportsStatus: reportsStatus || (prior?.reportsStatus ?? false),
            force: force || (prior?.force ?? false)
        )
        peakPending = max(peakPending, pending.count)

        guard task == nil || force else { return }
        let previous = task
        if force { previous?.cancel() }
        startWorker(force: force, after: previous)
    }

    private func startWorker(
        force: Bool,
        after previous: Task<PersistenceFlushResult, Never>?
    ) {
        generation &+= 1
        let workerGeneration = generation
        task = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return .cancelled }
            if !force { try? await Task.sleep(for: Self.checkpoint) }
            return await self.drain(generation: workerGeneration)
        }
    }

    private func drain(generation workerGeneration: Int) async -> PersistenceFlushResult {
        defer {
            if generation == workerGeneration { task = nil }
        }

        while let assetID = pending.keys.sorted(by: { $0.description < $1.description }).first,
              let snapshot = pending[assetID] {
            guard !Task.isCancelled else { return .cancelled }
            do {
                try await store.save(snapshot.document, for: snapshot.reference)
                if pending[assetID] == snapshot { pending.removeValue(forKey: assetID) }
                if snapshot.reportsStatus {
                    lastFailureMessage = nil
                    onStatusChange?(nil)
                }
            } catch is CancellationError {
                return .cancelled
            } catch {
                let message = error.localizedDescription
                lastFailureMessage = message
                onStatusChange?(message)
                onFailure?(message)
                // Keep the snapshot dirty. A later edit or termination flush retries it rather than
                // presenting a durable state that never reached disk.
                return .failure(message)
            }
            if !snapshot.force, !pending.isEmpty {
                try? await Task.sleep(for: Self.checkpoint)
            }
        }
        return Task.isCancelled ? .cancelled : .success
    }

    /// Replace a checkpoint worker with a serialized, immediate worker. The old worker is awaited
    /// by the replacement so an already-started actor write cannot be orphaned.
    func requestFlush() {
        guard !pending.isEmpty else { return }
        let previous = task
        previous?.cancel()
        startWorker(force: true, after: previous)
    }

    /// Wait until all queued snapshots are durable or return the actionable failure.
    func flush() async -> PersistenceFlushResult {
        guard !Task.isCancelled else { return .cancelled }
        requestFlush()
        while let current = task {
            let result = await current.value
            if Task.isCancelled { return .cancelled }

            // A concurrent forced flush may have replaced the worker we just awaited. Internal
            // cancellation is not the final result while dirty snapshots remain.
            if task != nil, !pending.isEmpty { continue }
            if result == .cancelled, pending.isEmpty { return .success }
            return result
        }

        return pending.isEmpty
            ? .success
            : .failure(lastFailureMessage ?? "Could not save pending edit records")
    }

    /// Abandon snapshots only after the user explicitly chose Quit Without Saving.
    func discard() async {
        let current = task
        current?.cancel()
        pending.removeAll()
        if let current { _ = await current.value }
    }
}
