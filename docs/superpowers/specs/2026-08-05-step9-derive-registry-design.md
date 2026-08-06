# Phase 2 Step 9 — wire derive into the new state

**Date:** 2026-08-05
**Ship gate (`PHASE2_SPEC.md` §6):** register the derived LUT by ID, keep the scratch-file
bookkeeping; derive-baseline invariance test.

---

## 1. The bug this step exists to fix

A derived LUT does not resolve. It is on `main` today, it is not something the migration is about to
introduce, and it is verified rather than reasoned about.

`DeriveCoordinator.derive` builds its result as `CubeLUT(…, sourceURL: scratch)`. `CubeLUT.init`
therefore sets `id = sourceURL.path` — a temp-file path — so `LUTID.isDerived`, which tests
`raw.hasPrefix("derived://")`, is **false**. `AppViewModel.selectLUT` reads:

```swift
scratchLUT = (lut?.lutID.isDerived == true) ? lut : nil   // → nil
document.lut.lutID = lut?.lutID                            // → the temp path
```

`resolvedLUT` then misses the (nil) scratch slot and falls through to
`library.allLUTs.first(matching:)`, where a temp path is never found. Measured against the exact
construction `DeriveCoordinator` uses:

```
id:          /var/folders/…/T/probe_recipe_2_Rec709.cube
isDerived:   false
selectedLUT: nil          ← after derive.onDerived?(lut)
documentID:  /var/folders/…/T/probe_recipe_2_Rec709.cube
```

So a successful derive leaves the preview **ungraded** with nothing selected in the sidebar.
`onDerived` → `selectLUT` is the only path that selects a fresh derive; nothing re-selects it later.

Two shipped tests cover this area and both pass, because both build their fixture with
`CubeLUT(cube:size:name:)` and **no `sourceURL`** — which yields a `derived://…` id and
`isDerived == true`. The fixture differs from production in exactly the field under test. That is
`CODE_REVIEW.md` §2's "wrote a value that equals the default" pattern one level up, and fixing it is
part of this step.

---

## 2. Identity scheme

### 2.1 What was rejected

**Keep the scratch path as the ID, and key the registry by path.** Requires no change to
`DeriveCoordinator`. Rejected on two counts. `LUTID.isDerived` would stay `false` for a derived LUT,
leaving a predicate in the codebase that means the opposite of its name — the exact trap that
produced this bug. And a document holding `/var/folders/…/T/x.cube` is worse than dangling: after
the OS temp sweep that path can be **reused by an unrelated file**, so a stale reference can resolve
to the wrong LUT rather than to nothing.

### 2.2 What ships

**The derived LUT gets its `derived://` identity back, and the ID is content-derived.**

`DeriveCoordinator` stops passing `sourceURL:` into `CubeLUT.init`. The scratch `.cube` is still
written and still kept — that is `scratchURL`'s job and it is untouched — but the temp path no
longer *names* the LUT. `CubeLUT.init` then takes the synthetic branch, and that branch changes from

```swift
"derived://\(name)/\(UUID().uuidString)"
```

to a SHA-256 over the flattened cube table:

```swift
"derived://\(name)/\(sha256(tableData).prefix(8).hex)"    // 64 bits, e.g. derived://shot_recipe_33_Rec709/9f3a…
```

`isDerived` becomes true and means what it says; `selectLUT`'s existing branch starts working.

**Be honest about what the hash buys and does not buy.** It buys determinism *for a given cube
value*: the same table always yields the same ID, so nothing in the type mints fresh identity on
construction — which is §4.3's actual objection to `UUID`. It does **not** buy resurrection across a
relaunch by re-deriving: `RecipeExtractor` draws its samples with `SystemRandomNumberGenerator`
(`RecipeExtractor.swift:399`), so deriving twice from the same pair produces different cubes and
therefore different IDs. Anyone reading `derived://…/<hash>` and expecting re-derive to reproduce it
would be wrong.

`CryptoKit` is an Apple framework, so this does not touch the zero-third-party-dependency
constraint, and `SHA256` is macOS 10.15+ — no `#available` needed against the macOS 14 target.
Swift's own `Hasher` is deliberately **not** used: it is seeded per process, so it would be stable
within a launch and silently different across launches, which is the failure mode §4.3 warns about
wearing a different hat.

### 2.3 The two properties this reverses

Content-hashing makes two identically-constructed in-memory LUTs **equal**, where today they are
distinct. Two shipped tests assert the old property by name and both must be rewritten deliberately,
not silenced:

| test | asserts today | asserts after |
|---|---|---|
| `LUTIDTests.testInMemoryDerivedLUTsGetASyntheticID` | two in-memory derivations are two different LUTs | the same cube yields the same ID; a *different* cube yields a different one |
| `CubeLUTTests.testInMemoryLUTGetsSyntheticIDWhenNotFileBacked` | two in-memory LUTs must not collide as the same identity | identity follows contents, and a file-backed LUT is never mistaken for derived |

The new property is defensible on its own terms — two LUTs with the same table render identically
and are interchangeable in `LUTFilterCache`, so treating them as one identity is more correct than
treating them as two. It is still a reversal, and it is recorded here so it reads as a decision.

### 2.4 The registry

`AppViewModel.scratchLUT: CubeLUT?` — the single optional whose comment says "Step 9 replaces this
with a real registry" — becomes `DerivedLUTRegistry`, a small value type keyed by `LUTID`.

```swift
struct DerivedLUTRegistry {
    private var luts: [LUTID: CubeLUT] = [:]
    mutating func register(_ lut: CubeLUT)
    func lut(for id: LUTID) -> CubeLUT?
    var count: Int          // internal, for tests: membership has no other observable trace
}
```

A struct rather than a class because only `AppViewModel` needs it and a value keeps the Swift 6
story trivial. It holds derived LUTs **and their saved successors** (§3) — the name describes where
its entries come from, not that every entry has a `derived://` ID. A file-backed entry that the
library also carries is harmless duplication: `CubeLUT` compares by ID, so both copies are the same
LUT. Resolution becomes registry-first, library-second:

```swift
private func resolvedLUT(_ id: LUTID?) -> CubeLUT? {
    guard let id else { return nil }
    if let registered = derivedRegistry.lut(for: id) { return registered }
    return library.allLUTs.first(matching: id)
}
```

**Unbounded, by decision.** A 33³ cube is ~575 KB of table and a derive costs the user tens of
seconds of wall clock, so a session cannot realistically grow this to a size worth managing. An LRU
would buy a bound nobody reaches and would let an older document silently stop resolving mid-session,
which is precisely what Step 11's undo will depend on not happening.

---

## 3. What happens after the save, and after a relaunch

A derived LUT has two identities across its life — a `derived://` content hash, then a user-chosen
library path. §4.3 forces an answer for the moment between them.

**On save**, `AppViewModel` re-parses the destination file, registers *that* LUT, and re-points the
document at it:

```swift
private func adoptSavedLUT(at destination: URL) {
    guard let saved = try? CubeLUT(url: destination, category: "Derived") else { return }
    derivedRegistry.register(saved)
    guard let current = document.lut.lutID,
          current == derive.derivedLUT?.lutID else { return }   // only the LUT that was just saved
    document.lut.lutID = saved.lutID
    schedulePreview()
}
```

Three deliberate choices in there:

- **Re-parse rather than alias the in-memory cube.** `CubeLUT.cubeFileContents` writes `%.6f`, so
  what lands on disk is a rounded copy of the in-memory table. Aliasing the full-precision cube to
  the saved path would leave the app rendering something a fresh launch could not reproduce from the
  same file — a preview/file divergence of exactly the kind this migration exists to close. The
  magnitude will be measured and recorded; it is expected to be 0/255, and the argument stands either
  way because it is about which value is authoritative, not about how big the gap is.
- **Re-point, so the reference becomes durable at the moment the LUT does.** After the save the
  document holds a real library path, which survives the temp sweep and survives a relaunch.
- **Register as well as re-point**, so a save *outside* the LUT folder still resolves. `onSaved`
  only triggers a rescan when `library.folderURL` is set and the file landed under it; the registry
  covers the rest.

**After a relaunch**, a saved derive resolves by path like any other library LUT. An unsaved one
dangles — by design — and `isDerived` is how a persistence layer detects that, which is exactly what
`LUTID`'s doc comment already promises. Step 9 makes that comment true rather than aspirational.
Persistence itself stays out of scope (§8.8: v1 is in-memory only).

**Scratch-file policy is unchanged.** A cancelled derive still writes nothing; a completed one still
keeps its scratch file so the sheet can be reopened, still deletes the previous one when a new derive
starts, and is still left to the OS temp sweep. `CODE_REVIEW.md` §2's `[partly fixed]` stays
`[partly fixed]`.

---

## 4. `invalidateLUTCache` — Step 9 closes it

It exists, it is tested, and the only caller is a test. Step 9 closes it, not on general principle
but because Step 9 makes it **reachable**:

> Derive A → Save to `X.cube` → derive B → Save to `X.cube` again.

Same path, therefore same `LUTID`, therefore `LUTFilterCache` keeps serving A's filter and the second
save silently has no effect on screen. Without the re-point in §3 the user could not get there;
with it, they can.

Two changes:

- `invalidateLUTCache()` moves onto the `RenderEngining` protocol, so `FakeRenderEngine` can record
  it and a test can assert it fired. It is currently unassertable from above the actor.
- `LUTLibrary` gains an `onScanned: (() -> Void)?` closure, fired after every scan publishes.
  `AppViewModel` wires it to the invalidation. A closure rather than a call at each scan site because
  it covers *every* scan structurally — including `restoreFolder` — instead of relying on the next
  person to remember. It matches the `onStatus`/`onError`/`onDerived`/`onSaved` idiom already in use.

Derive itself needs no invalidation: a new cube is a new content hash is a new cache key.

`RecipeExtractor` does **not** move onto the engine — it keeps its own `CIContext` and its
sRGB-pinned sampling space (§3, §4.4). `RenderStackTests` is untouched, which is the correct outcome
rather than a dodged one.

---

## 5. Testing

### 5.1 Fixture drift, fixed at the root

Rather than patching the two weak tests one at a time, extract the construction so a fixture
*cannot* differ from production:

```swift
extension DeriveCoordinator {
    nonisolated static func makeDerivedLUT(cube: [SIMD3<Float>], size: Int, name: String) -> CubeLUT
}
```

`derive` calls it; every test builds its derived LUT through it. A future change to how derive names
or constructs its LUT then breaks the tests instead of passing them.

Call sites to convert: `AppViewModelTests.testDerivedLUTIsSelectedWhenAnImageIsOpen`,
`PreviewCutoverTests.testTheShimsTrackTheDocument`, `DeriveCoordinatorTests.installScratchResult`.

### 5.2 New tests

| test | pins |
|---|---|
| `testAFreshlyDerivedLUTResolves` | the headline bug: after `onDerived`, `selectedLUT` is the derived LUT and the document holds its ID |
| `testSavingRepointsTheDocumentAtTheSavedFile` | the document's ID moves from `derived://…` to the destination path |
| `testSavingOutsideTheLibraryFolderStillResolves` | the registry covers the no-rescan case |
| `testALibraryScanInvalidatesTheEngineLUTCache` | the `onScanned` → `invalidateLUTCache` wiring, via `FakeRenderEngine` |
| `testAnEditedCubeAtTheSamePathRendersTheNewLook` | the real engine: same `LUTID`, new file contents, different pixels after invalidation |
| rewrites of the two §2.3 tests | identity follows contents |

### 5.3 The ship gate: derive-baseline invariance

The property to pin is that the cube `RecipeExtractor` fits is still fit against the same neutral RAW
render the pipeline produces. `RenderPipelineTests.testNeutralRAWMatchesTheExistingNeutralBaseline`
and `WorkingSpaceTests.testDeriveFitSpaceEqualsApplySpace` already pin the two halves separately;
what is missing is the end-to-end link.

New `DeriveInvarianceTests`, derived from the `realworldtest` (DNG, in-camera JPG) pair, **interleaved
in one process** because Core Image is not bit-reproducible across time-separated runs:

1. Derive a cube from the pair.
2. Render (a) `ImageDecoder.developRAWNeutral` + `cube.apply(space: .sRGB)` — the way
   `RecipeExtractor` fits it.
3. Render (b) `RenderPipeline.buildImage(source:document:lut:scale:.full)` — the new pipeline.
4. Assert (a) and (b) agree at the repo's parity tolerance of 1.
5. Separately, assert mean absolute error of (b) against the in-camera JPG stays under a bound. The
   bound is set from the measured value with stated headroom and the measurement recorded in the test
   — no number pulled from the air. This half exists so a wholly broken derive fails rather than
   passing a self-consistency check trivially.

Step 4 is the strict half and needs no magic number, because both sides are computed in the same run.
Step 5 is the sanity floor.

**This test skips in CI.** `Fixtures.localRAWURL` finds nothing on a runner, and CI never has a DNG.
That will be stated in the skip message, in the PR body, and in the migration table — a locally-only
test that reads as coverage is worse than no test.

### 5.4 Mutation checks

Every regression test above gets mutation-checked with a scripted harness that reports **caught**,
**survived**, **did not compile**, **no tests ran**, and **skipped** as separate outcomes — a
mutation that fails to build otherwise counts as a pass. Survivors are triaged individually; where
one is genuinely equivalent, that is proved by measurement and recorded, not reclassified.

---

## 6. Files touched

| file | change |
|---|---|
| `Models/CubeLUT.swift` | synthetic ID becomes a content hash; `tableData` built before `id` |
| `Models/LUTSettings.swift` | `LUTID.isDerived` doc comment: UUID → content hash |
| `Models/DerivedLUTRegistry.swift` | **new** |
| `Models/RenderEngine.swift` | `invalidateLUTCache()` onto the `RenderEngining` protocol |
| `Models/LUTLibrary.swift` | `onScanned` closure |
| `ViewModels/DeriveCoordinator.swift` | `makeDerivedLUT`; stop passing `sourceURL:` |
| `ViewModels/AppViewModel.swift` | registry replaces `scratchLUT`; `adoptSavedLUT`; wire `onScanned` |
| tests | §5 |
| `docs/PHASE2_SPEC.md` | §2 baseline row, §6 Step 9 → done |
| `docs/CODE_REVIEW.md` | note that the scratch policy is unchanged and the cache hole is closed |

## 7. Out of scope

Edit persistence across launches (§8.8), per-image undo and `EditDocumentStore` (Step 11), the RAW
develop inspector (Step 10), `RecipeExtractor.Options` UI, and `RecipeReport.alignmentShift`
rendering. None are needed for the gate and each is already tracked.
