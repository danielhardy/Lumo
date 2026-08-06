import Foundation

/// The LUTs a document can reference that no folder scan will ever produce.
///
/// `AppViewModel` resolves `document.lut.lutID` against the library, which is a scan of a folder on
/// disk. A freshly derived LUT is not on disk anywhere the library looks — it lives in memory until
/// the user saves it — so without somewhere else to look, a document referencing one resolves to
/// `nil` and the image renders ungraded. That was the shipping behaviour before Step 9.
///
/// This replaces the single `scratchLUT: CubeLUT?` slot that stood in for it. A single slot could
/// only ever hold the *latest* derive, which is the wrong shape for two reasons: Step 11's per-image
/// undo will hold documents referencing earlier ones, and a derive that has since been saved needs
/// to stay reachable under both its identities (§3 of the Step 9 design).
///
/// **Unbounded, by decision.** A 33³ cube is ~575 KB of table and a derive costs the user tens of
/// seconds of wall clock, so a session cannot realistically grow this to a size worth managing. An
/// LRU would buy a bound nobody reaches, and its eviction would let an older document silently stop
/// resolving mid-session — exactly what undo will depend on not happening.
///
/// A value type: only `AppViewModel` needs one, and keeping it a value means there is no shared
/// mutable reference for Swift 6 to have an opinion about.
struct DerivedLUTRegistry {

    private var luts: [LUTID: CubeLUT] = [:]

    /// Remember `lut` under its own ID.
    ///
    /// Re-registering the same ID overwrites, which is correct rather than merely tolerable: IDs are
    /// content-derived, so two LUTs sharing one are the same cube under the same name.
    mutating func register(_ lut: CubeLUT) {
        luts[lut.lutID] = lut
    }

    /// The LUT registered under `id`, if any.
    func lut(for id: LUTID) -> CubeLUT? {
        luts[id]
    }

    /// How many LUTs are held. Internal for tests: membership has no other observable trace, and a
    /// registry that silently stopped registering would look exactly like one that never needed to.
    var count: Int { luts.count }
}
