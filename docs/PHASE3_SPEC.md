# Lumo Phase 3 — Photo Intelligence, shared mask foundation & subject-aware Auto

**Status:** not started. This is the implementation plan for a reusable, deterministic
photo-understanding layer, built as a first-class subsystem rather than as "the code behind the
Auto button." It is a distillation of a longer architectural proposal (48 numbered principles,
plus a follow-up correction on mask sequencing) preserved in the DG ticket bodies it was split
into (`LUMO-181` and its children `LUMO-182`–`LUMO-207`) — this document carries only what is
load-bearing for implementation. Per-component transcripts belong in the PR that implements each
step, not here.

---

## 1. What Phase 3 is for

Lumo ships one Auto today: `AutoAdjustmentSettings` / `AutoImageStatistics` /
`AutoAdjustmentAnalyzer` in
[`Sources/LumoKit/Models/AutoAdjustment.swift`](../Sources/LumoKit/Models/AutoAdjustment.swift),
wired up in `AppViewModel.runAutoAdjustment()`
([`AppViewModel.swift:861`](../Sources/LumoKit/ViewModels/AppViewModel.swift)). It reads a 256-bin
luma/RGB histogram from `RenderEngine.histogram(...)` and sets global Light + Color values. It has
**no notion of subject, face, or background** — every pixel counts equally. That is Tier 0 in the
tier scheme below, and Phase 3 does not replace it; Phase 3 adds the tiers above it and, only in
step 20 (`LUMO-200`), gives `runAutoAdjustment()` a second, richer source of truth to call into.

**The scope is deliberately wider than "Auto's internals."** A second consumer — a user-facing
Masking feature (`LUMO-201`) — is designed in from the start and shares the exact same mask
infrastructure Auto uses. See §2 for why that ordering is binding, not incidental.

---

## 2. Architecture (binding) — masks are shared infrastructure, built before regional analysis

**This is the single most important decision in this document.** An earlier draft of this plan
built masks as a private concept inside `PhotoAnalysis` and treated a masking UI as a late add-on
gated behind Auto. That was revised before any implementation started, because it leads to
duplicated Vision calls, duplicated caches, subtly different masks for the same photo, and
coordinate-system bugs between two independently-built mask paths.

The binding dependency chain:

```text
IMAGE ANALYSIS FOUNDATION            (coordinate system, canonical AnalysisImage)
        ↓
MASK FOUNDATION                      (RegionMask, MaskStore, MaskOperations,
                                       SemanticMaskProviding protocol)
        ↓
VISION MASK PROVIDERS                (subject, face, foreground/background, person —
                                       each a SemanticMaskProviding conformer)
        ↓
REGIONAL PHOTO ANALYSIS              (masked statistics → PhotoAnalysis assembly →
                                       primary-subject ensemble → relationships →
                                       scene characteristics)
       ↙ ↘
   Auto Light Engine          User-facing Masking UI
        ↓                              ↓
   (both consume the identical RegionMask through the identical
    SemanticMaskProviding / MaskedToneAnalyzer seam — the only
    difference is requested MaskQuality: Auto uses .analysis,
    the UI uses .preview/.render)
```

Concretely, from the architecture proposal, Auto's internal call:

```swift
let subjectMask = maskService.mask(for: .subject, image: image, quality: .analysis)
let stats = toneAnalyzer.statistics(image: image, through: subjectMask)
```

and the Masking UI's call, later, is the *same* call at a different quality:

```swift
let mask = maskService.mask(for: .subject, image: image, quality: .preview)
```

Neither consumer is allowed a private mask representation, cache, or Vision call path. A useful
downstream consequence: "Select Subject" and similar masking-UI affordances are not new ML work
when they're built — they expose capabilities Auto already required and proved.

**The rule that matters most, otherwise unchanged:** the Auto engine never imports Vision or Core
Image types. It consumes `PhotoAnalysis`/`RegionMask`, Lumo-owned `Sendable, Codable` values. This
mirrors the pattern Phase 2 already established for rendering (`EditDocument` → pure
`RenderPipeline.buildImage` → `actor RenderEngine`, see `PHASE2_SPEC.md` §3).

### Concurrency shape (binding, matches CLAUDE.md's Swift 6 rules)

- Vision adapters (`VisionSemanticMaskProvider`) and coordinators (`PhotoAnalysisCoordinator`,
  `MaskStore`) are `actor`s (mirrors `actor RenderEngine`).
- `RegionMask`, `PhotoAnalysis`, and everything inside them are `Sendable, Codable, Equatable`
  value types with **zero** escape hatches: no `@unchecked Sendable`, no `nonisolated(unsafe)`, no
  `@preconcurrency`. `PackageSettingsTests` already fails the whole module if any of those appear
  anywhere in `Sources`; this subsystem does not get an exemption.
- `AutoLightEngine` is ordinary `Sendable` value-in/value-out code with no actor isolation
  requirement at all — like `RenderPipeline.buildImage`, callable and testable without `await`.
- Nothing in this subsystem requires `@MainActor` except UI-layer code (the Masking panel, the
  "apply this `EditParameters` to the document" step, which already exists as
  `AppViewModel.updateDocument`).

---

## 3. Mask foundation (binding shapes)

```swift
enum SemanticMaskKind: Sendable, Codable, Equatable, Hashable {
    case subject
    case background
    case person
    case face            // may need an associated index for multi-face photos — LUMO-189 decides
    case foregroundInstance(Int)
}

enum MaskQuality: Sendable, Codable, Equatable, Comparable {
    case analysis   // ~768px canonical image — what Auto always uses
    case preview     // Masking UI's live selection view
    case render      // full-res / tile-based — local-adjustment painting (LUMO-202)
}

struct RegionMask: Sendable, Codable, Equatable, Identifiable {
    let id: RegionID
    let kind: SemanticMaskKind
    let bounds: NormalizedRect
    let quality: MaskQuality
    let reference: RegionMaskReference   // pointer into MaskStore — pixels never embedded inline
    let confidence: Float
    let coverage: Float
}

protocol SemanticMaskProviding: Sendable {
    func mask(
        for kind: SemanticMaskKind,
        image: AnalysisImage,
        quality: MaskQuality
    ) async throws -> RegionMask
}
```

Today's implementation is `VisionSemanticMaskProvider`. Nothing outside it may know *how* a mask
was produced — a future `CoreMLSemanticMaskProvider` (or Apple's next-generation API) is a
drop-in replacement neither Auto nor the Masking UI needs to know about.

`MaskOperations` (`invert`, `intersect`, `union`, `subtract`, `feather`, `refine`) lets both
consumers combine masks (e.g. "everything except the subject," "person minus face") without either
reimplementing pixel-level compositing.

---

## 4. Analysis domain model (binding shapes)

`PhotoAnalysis` states facts about the image; nothing in it may contain a recommended slider
value.

```swift
struct AnalyzedRegion: Sendable, Codable, Equatable, Identifiable {
    let id: RegionID
    let kind: RegionKind          // mirrors SemanticMaskKind
    let mask: RegionMaskReference
    let confidence: Float
    let importance: Float
    let tone: ToneStatistics
    let color: ColorStatistics
    let coverage: Float
}

struct PhotoAnalysis: Sendable, Codable, Equatable {
    let version: AnalysisVersion
    let globalTone: ToneStatistics
    let colorStatistics: ColorStatistics
    let regions: [AnalyzedRegion]
    let relationships: RegionRelationships
    let scene: SceneCharacteristics
    let quality: AnalysisQuality
    let timings: AnalysisTimings
}
```

Coordinates: one canonical system, `NormalizedRect`/`NormalizedPoint`/`NormalizedMask`, origin
upper-left, 0...1. Vision's own normalized-coordinate convention (and RAW/EXIF orientation) is
converted **once**, at the Vision adapter boundary. Nothing downstream — masks, regions, Auto,
the Masking UI — may touch a raw `CGRect` from Vision.

---

## 5. Analysis tiers and the demand-driven pipeline

Every analyzer/mask provider runs against **one** canonical downscaled image (target ~768px
longest edge, configurable, benchmarked in `LUMO-206`), produced **once** by an
`AnalysisImageFactory`. No analyzer resizes or re-renders the source itself.

```
Tier 0  global tone/color         — required; Auto must degrade to this alone if everything else fails
Tier 1  subject mask (saliency)   — optional
Tier 2  foreground/background masks — optional, only computed when useful
Tier 3  face / person masks       — optional, person gated on face/foreground signals
```

Three quality presets select which tiers run and at what `MaskQuality`:

| Level | Used for | Roughly |
|---|---|---|
| `.fast` | browsing, thumbnails, prefetch | 512px, global stats, `.analysis`-quality face/subject |
| `.standard` | Auto button, editor entry | 768px, + foreground/background, regional analysis |
| `.detailed` | Masking UI selection, local adjustments | `.preview`/`.render`-quality masks |

Analysis is demand-driven: a caller asking only "where is the important region" should not pay
for a full person-segmentation matte. **Failure is data, not fatal** — `PhotoAnalysis.quality`
records which tiers actually populated; only failure to obtain Tier 0 should prevent Auto from
producing a result.

---

## 6. Cancellation, dedup, caching

- Every analysis/mask entry point is `async` and cooperatively cancellable — mirrors
  `runAutoAdjustment()`'s `autoAdjustmentTask?.cancel()`.
- `PhotoAnalysisCoordinator` (actor) deduplicates concurrent requests for the same
  `(assetID, sourceFingerprint, level)` or `(assetID, sourceFingerprint, kind, quality)` — the
  Masking UI's direct mask requests and Auto's full-analysis requests share the same in-flight
  work and the same cache when they overlap.
- **Two caches, split by what they store:** `MaskStore` (`LUMO-185`) persists mask *pixel* data,
  keyed by asset identity + source fingerprint + `SemanticMaskKind` + `MaskQuality` + provider
  version — independently per quality level. `PhotoAnalysisCache` (`LUMO-196`) persists the small
  scalar `PhotoAnalysis` facts, keyed by asset identity + source fingerprint + analysis version.
  Both share the same `SourceFingerprint` definition so they can't disagree about invalidation.
- Moving a slider (exposure, LUT, …) must **not** invalidate either cache — both describe the
  *source* scene (post RAW-decode/orientation, pre creative edits). Re-deriving on every Light
  change would create a feedback loop (Auto changes exposure → analysis changes → Auto changes
  exposure again).

---

## 7. Performance and memory budgets (engineering targets, not guarantees)

| Path | Target |
|---|---|
| Cache hit | < 5 ms |
| Tier 0 only | < 20 ms |
| Fast subject-aware | < 75 ms |
| Standard (Auto) | < 150 ms |
| Detailed segmentation / `.render`-quality mask | < 300 ms |

Transient working memory for a standard analysis should stay well under ~50 MB. `.render`-quality
mask refinement (`LUMO-202`) is tile-based specifically to keep full-resolution work within
budget rather than materializing a full-res buffer at once. Editor UI must never block
synchronously on analysis or masking; every call site awaits a `Task`.

---

## 8. Quality infrastructure

Fixture corpus (`LUMO-204`), golden semantic expectations, and the visual regression harness
(`LUMO-205`) are early tickets, not backlog-someday items — they're what let the tuning pass
(`LUMO-207`) and future agent-driven changes be verified against real behavior. Golden tests
assert semantic facts and *ranges*, never exact float equality.

---

## 9. Privacy and dependency constraints (binding, matches CLAUDE.md)

- No image data leaves the device for analysis or masking. No network fallback is architected in.
- Apple frameworks only: Vision, Core Image, Accelerate, Metal where justified. No third-party ML
  runtime, no Core ML model bundle in this phase.
- macOS 14 minimum still applies. Verify the minimum OS for every Vision API used
  (`GenerateAttentionBasedSaliencyImageRequest` / `GenerateForegroundInstanceMaskRequest` are
  recent), `#available`-guard, and fall back gracefully — consistent with the `RAWDevelopSettings`
  precedent in CLAUDE.md's "SDK vs deployment target" section.

---

## 10. Ticket sequence

Filed as DG tickets under epic `LUMO-181`. Each ticket is independently reviewable with its own
acceptance criteria; do not collapse these into fewer, larger tickets.

| # | Ticket | Deliverable | Depends on |
|---|---|---|---|
| 1 | `LUMO-182` | Core analysis value types (`ToneStatistics`, `ColorStatistics`, quality/timings) | — |
| 2 | `LUMO-183` | `AnalysisImage` pipeline + normalized point/rect coordinate system | 182 |
| 3 | `LUMO-184` | **`RegionMask` core abstraction** (mask type, semantic kinds, quality levels, `SemanticMaskProviding`) | 183 |
| 4 | `LUMO-185` | `MaskStore`: mask caching and versioning | 184 |
| 5 | `LUMO-186` | `MaskOperations`: invert/intersect/union/subtract/feather/refine | 184 |
| 6 | `LUMO-187` | Vision semantic mask provider boundary | 183, 184 |
| 7 | `LUMO-188` | Attention saliency → subject mask provider | 187, 185 |
| 8 | `LUMO-189` | Face detection + face mask provider | 187, 185 |
| 9 | `LUMO-190` | Foreground instance + background mask provider | 187, 185 |
| 10 | `LUMO-191` | Person segmentation mask provider | 189, 190 |
| 11 | `LUMO-192` | Global tone + color statistics analyzer (Tier 0) | 182, 183 |
| 12 | `LUMO-193` | Masked regional statistics engine (`statistics(image:through:)`) | 184, 186, 192 |
| 13 | `LUMO-194` | `PhotoAnalysis` domain model assembly | 188, 189, 190, 191, 193 |
| 14 | `LUMO-195` | Analysis coordinator: cancellation + request dedup | 187, 192 |
| 15 | `LUMO-196` | Persistent `PhotoAnalysis` cache + versioning | 195, 194 |
| 16 | `LUMO-197` | Primary subject ensemble scoring | 194 |
| 17 | `LUMO-198` | Region relationships (subject/background/face deltas) | 197 |
| 18 | `LUMO-199` | Scene characteristics (backlighting / high-key / low-key) | 198 |
| 19 | `LUMO-200` | Auto Light engine (pure function, composable evaluators) | 199 |
| 20 | `LUMO-201` | **User-facing Masking UI** (Select Subject/Person/Background/Face) | 186, 188, 189, 190, 191 — *not* Auto |
| 21 | `LUMO-202` | High-quality mask refinement (full-res/tile-based) | 201, 186 |
| 22 | `LUMO-203` | Debug analysis + mask visualization overlay | 194 |
| 23 | `LUMO-204` | Fixture photo corpus + golden semantic expectations | 200 |
| 24 | `LUMO-205` | Visual regression harness | 204 |
| 25 | `LUMO-206` | Performance instrumentation + benchmark suite | 196, 190 |
| 26 | `LUMO-207` | Auto tuning across corpus | 200, 204, 205 |

Note `LUMO-201` (Masking UI) depends on the mask providers directly, not on `LUMO-200` (Auto) —
it's sequenced after Auto in the table for product-delivery reasons, but is not technically
blocked by it; an agent could pick it up as soon as `188`–`191` and `186` land.

Full acceptance criteria, implementation notes, and file pointers live in each ticket
(`dg context <id>` / `dg issue show <id>`), not here.
