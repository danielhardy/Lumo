import Foundation
import CoreImage

/// Reusable `CIColorCubeWithColorSpace` filters, keyed by LUT **and** colour space.
///
/// Building one of these is not free: `CubeLUT.makeFilter` hands Core Image the whole flattened cube,
/// which for a 65³ LUT is 65³ × 4 floats ≈ **4.4 MB**. Rebuilding it per render — and a slider drag is
/// many renders — is the kind of cost that does not show up in a screenshot but does show up in a
/// scrub.
///
/// **The key includes the colour space**, because the cube is interpolated in it: the same LUT in sRGB
/// and in Display P3 are two different filters, and returning one for the other would silently break
/// the lockstep the `WorkingSpace` seam exists to guarantee.
///
/// **Deliberately not `Sendable`.** `CIFilter` is a mutable reference type and using a cached one means
/// writing `inputImage` to it, so a shared instance across concurrent renders would be a data race.
/// This is owned by `actor RenderEngine` (Step 4), which serializes access — the GPU boundary is the
/// isolation boundary. See `docs/PHASE2_SPEC.md` §4.5.
///
/// Reusing a filter is safe *because* `CIFilter.outputImage` snapshots the current inputs into an
/// immutable image graph rather than reading them lazily at render time. That is load-bearing for this
/// whole type, so `LUTFilterCacheTests` verifies it rather than trusting it.
final class LUTFilterCache {

    /// How many filters to keep. Small on purpose: at 4.4 MB for a 65³ cube, an unbounded cache over a
    /// browsed library of a hundred looks would pin hundreds of MB for filters the user has moved past.
    /// Eight covers A/B-ing a handful of looks, which is the access pattern that actually repeats.
    static let defaultCapacity = 8

    private struct Key: Hashable {
        let lut: LUTID
        let space: WorkingSpace
    }

    private var filters: [Key: CIFilter] = [:]
    /// Least-recently-used first. Short enough that a linear scan beats a linked list.
    private var usage: [Key] = []

    let capacity: Int

    init(capacity: Int = LUTFilterCache.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// The cube filter for `lut` in `space`, built on first use and reused after.
    ///
    /// Returns `nil` only if Core Image cannot create the filter at all, which `CubeLUT.makeFilter`
    /// already treats as a failure. A `nil` is not cached — a transient failure should not poison the
    /// entry for the rest of the session.
    func filter(for lut: CubeLUT, space: WorkingSpace = .current) -> CIFilter? {
        let key = Key(lut: lut.lutID, space: space)

        if let cached = filters[key] {
            touch(key)
            return cached
        }
        guard let made = lut.makeFilter(space: space) else { return nil }

        filters[key] = made
        usage.append(key)
        evictIfNeeded()
        return made
    }

    /// Drop everything. For the library being rescanned or replaced — a `LUTID` is a path, so a file
    /// edited in place would otherwise keep serving the old cube.
    func removeAll() {
        filters.removeAll()
        usage.removeAll()
    }

    /// How many filters are currently held. Exists for the tests that pin the eviction policy.
    var count: Int { filters.count }

    private func touch(_ key: Key) {
        if let index = usage.firstIndex(of: key) {
            usage.remove(at: index)
        }
        usage.append(key)
    }

    private func evictIfNeeded() {
        while usage.count > capacity {
            let oldest = usage.removeFirst()
            filters[oldest] = nil
        }
    }
}
