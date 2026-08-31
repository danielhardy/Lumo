import Foundation

/// The observable counters shared by the in-memory caches.
struct CacheStatistics: Sendable, Equatable {
    let hits: Int
    let misses: Int
    let evictions: Int
    let count: Int
    let costBytes: Int
}

struct RenderCacheConfiguration: Sendable, Equatable {
    var previewMaxEntries = 12
    var previewMaxCostBytes = 64 * 1024 * 1024
    var developedSourceMaxEntries = 4
    var developedSourceMaxCostBytes = 256 * 1024 * 1024

    static let `default` = Self()
}

struct RenderCacheStatistics: Sendable, Equatable {
    let preview: CacheStatistics
    let developedSource: CacheStatistics
}

/// An actor-local least-recently-used cache.
///
/// Values are intentionally not required to be `Sendable`: the developed-source cache stores
/// `CIImage`, which must remain inside `RenderEngine`. The owner provides the isolation. A byte cost
/// is supplied by the caller because Core Image intermediates are opaque reference values.
final class BoundedLRUCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let cost: Int
    }

    private let maxEntries: Int
    private let maxCostBytes: Int
    private var entries: [Key: Entry] = [:]
    private var recency: [Key] = []
    private var totalCostBytes = 0
    private var hitCount = 0
    private var missCount = 0
    private var evictionCount = 0

    init(maxEntries: Int, maxCostBytes: Int) {
        self.maxEntries = max(0, maxEntries)
        self.maxCostBytes = max(0, maxCostBytes)
    }

    func value(for key: Key) -> Value? {
        guard let entry = entries[key] else {
            missCount += 1
            return nil
        }
        hitCount += 1
        touch(key)
        return entry.value
    }

    func insert(_ value: Value, for key: Key, cost: Int) {
        let boundedCost = max(0, cost)
        if let old = entries.removeValue(forKey: key) {
            totalCostBytes -= old.cost
            recency.removeAll { $0 == key }
        }

        guard maxEntries > 0, maxCostBytes > 0, boundedCost <= maxCostBytes else {
            if boundedCost > maxCostBytes { evictionCount += 1 }
            return
        }

        entries[key] = Entry(value: value, cost: boundedCost)
        recency.append(key)
        totalCostBytes += boundedCost
        trimToLimits()
    }

    func removeAll(countAsEvictions: Bool = false) {
        if countAsEvictions { evictionCount += entries.count }
        entries.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
        totalCostBytes = 0
    }

    var count: Int { entries.count }

    var statistics: CacheStatistics {
        CacheStatistics(
            hits: hitCount, misses: missCount, evictions: evictionCount,
            count: entries.count, costBytes: totalCostBytes
        )
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func trimToLimits() {
        while entries.count > maxEntries || totalCostBytes > maxCostBytes {
            guard let oldest = recency.first, let removed = entries.removeValue(forKey: oldest) else {
                break
            }
            recency.removeFirst()
            totalCostBytes -= removed.cost
            evictionCount += 1
        }
    }
}
