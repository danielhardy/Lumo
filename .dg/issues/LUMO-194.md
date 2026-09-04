---
id: LUMO-194
title: PhotoAnalysis domain model assembly
type: feature
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:53.354Z
updated: 2026-09-04T14:34:42.822Z
depends_on:
  - LUMO-188
  - LUMO-189
  - LUMO-190
  - LUMO-191
  - LUMO-193
order: zzzzzh
board: product
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/PhotoAnalysis.swift` (assembly)
**Depends on:** LUMO-188, LUMO-189, LUMO-190, LUMO-191, LUMO-193
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §3

## 1. Problem

With mask providers (LUMO-188/189/190/191) and masked statistics (LUMO-193) both in place, this
ticket assembles the full `PhotoAnalysis` struct — the facts-only, `Sendable`/`Codable` value that
Auto (LUMO-197+) will eventually consume. This is later in the sequence than an earlier draft of
this plan had it, deliberately: `PhotoAnalysis` is now a *consumer* of the mask foundation, not
something masks get bolted onto afterward.

## 2. Requirement (acceptance criteria)

1. `struct AnalyzedRegion: Sendable, Codable, Equatable, Identifiable` — a thin pairing of a
   `RegionMask` (LUMO-184) reference with the statistics computed through it (LUMO-193):
   `id`, `kind: RegionKind`, `mask: RegionMaskReference`, `confidence: Float`, `importance:
   Float`, `tone: ToneStatistics`, `color: ColorStatistics`, `coverage: Float`. `RegionKind`
   mirrors `SemanticMaskKind` (LUMO-184) but is the analysis-facing vocabulary — decide whether
   `RegionKind` is literally `SemanticMaskKind` reused, or a distinct-but-parallel enum, and
   document the choice; reusing one type is preferable unless a concrete reason forces a split.
2. `struct PhotoAnalysis: Sendable, Codable, Equatable` — `version: AnalysisVersion`, `globalTone:
   ToneStatistics`, `colorStatistics: ColorStatistics`, `regions: [AnalyzedRegion]`, `quality:
   AnalysisQuality`, `timings: AnalysisTimings` — all from LUMO-182/192/193. Fields for
   `relationships`/`scene` are added by LUMO-198/199 once those exist (either as `nil`-defaulted
   optionals added now, or the struct grows in those tickets — pick whichever keeps this ticket
   self-contained; adding the fields now as `nil`-able is simplest).
3. Assembly logic: given an `AnalysisImage` and the set of `RegionMask`s available (whichever of
   subject/background/person/face/foreground succeeded — gracefully skipping any that didn't, per
   `AnalysisQuality`), compute an `AnalyzedRegion` for each via LUMO-193, and produce one
   `PhotoAnalysis`.
4. Vision's own ontology (`VNFaceObservation`, `InstanceMaskObservation`, etc.) never appears here
   — everything arrived as `RegionMask` already, care of LUMO-188/189/190/191's conversion at
   their own boundary.
5. Every field states facts, never a recommendation — no `recommendedExposure` anywhere.
6. Pure assembly logic — no Vision, no actor isolation requirement (can be called from within the
   coordinator, LUMO-195, but doesn't require it).
7. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- This ticket is the natural place to also settle: does `PhotoAnalysis.regions` include a
  `.background` `AnalyzedRegion` always, or only when a foreground/subject was found? Document the
  answer — downstream tickets (relationships, scene characteristics) will assume it.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §3 — original domain-model shape, now revised per this ticket.
- LUMO-184 (`RegionMask`/`SemanticMaskKind`), LUMO-193 (`MaskedToneAnalyzer`) — direct inputs.

## 5. Testing

- `Tests/LumoKitTests/PhotoAnalysisAssemblyTests.swift` (new): assemble `PhotoAnalysis` from a
  full set of mock masks (all kinds succeed) and from a partial set (only Tier 0 + one mask kind
  succeeds) — assert `AnalysisQuality` correctly reflects what's present, and `Codable` round-trip
  holds for both. No masks at all (Tier-0-only) still produces a valid `PhotoAnalysis` with an
  empty `regions` array.
