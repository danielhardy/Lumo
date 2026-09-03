---
id: LUMO-081
title: Grain seed loses precision when converted to Float for the GPU kernel
type: task
status: done
priority: low
labels:
  - verification
created: 2026-09-01T05:02:45.324Z
updated: 2026-09-01T13:25:19.818Z
depends_on:
  - LUMO-038
order: zzzv
board: product
---

## Objective

Preserve full 32-bit seed entropy through `RenderPipeline.applyGrain` so unrelated source images cannot round to the same grain field.

## Context

Found during LUMO-038 verification (non-blocking). `RenderPipeline.grainSeed(for:)` derives a `UInt32` from a SHA256 digest of the source fingerprint (`Sources/LumoKit/Models/RenderPipeline.swift`), which is then passed to the `effectsGrain` CIKernel as `Float(seed)`:

```swift
arguments: [image, geometry, controls, Float(seed)]
```

`Float32` has a 24-bit mantissa. For values near 2^32, adjacent representable floats are ~256 apart, so distinct `UInt32` seeds within that range collide to the same `Float` and therefore the same noise field. Verified locally:

```swift
Float(UInt32(0xDEADBEEF)) == Float(UInt32(0xDEADBEEF) + 100)  // true
```

Since seeds are effectively random 32-bit values (SHA256-derived), this shrinks the seed space from 2^32 to roughly 2^24 buckets. Determinism itself is unaffected (the same seed always reproduces the same field — the existing LUMO-038 tests confirm this), but for large photo libraries the birthday bound means a small but non-zero number of unrelated images can end up sharing an identical grain pattern, which undercuts the intent of a per-asset deterministic field.

## Scope

- Pass the seed to the kernel with its full entropy preserved (e.g. split into two `Float` components, or pre-mix/decorrelate before truncation) so two different source fingerprints reliably produce visibly different fields.
- Should not change the grain field for currently-neutral or already-covered test seeds; add/adjust a test asserting that two seeds differing only in low bits (e.g. differing by 100) produce different fields.

## Out of scope

- Any change to the Amount/Size/Roughness mapping or the grain kernel's noise shaping.


### Comment — codex @ 2026-09-01T13:22:38.615Z

Implemented in commit 7202b04. RenderPipeline now splits each UInt32 grain seed into two exact UInt16 Float components and mixes them independently in the effectsGrain kernel, avoiding Float32 mantissa collisions while preserving neutral behavior and existing grain controls. Added regression coverage for seeds differing by 100 in low bits. Verification: swift test (463 passed, 25 expected skips), swift build -c release, git diff --check, and dg validate passed; validate reports the existing runner-model warning plus low-context warnings for LUMO-040/LUMO-081.


### Comment — claude @ 2026-09-01T13:25:18.039Z

## Counterpoint verification report (independent review)

**Verdict: PASS — no blockers.**

Reviewed commit 7202b04 against the objective and scope.

**Correctness**
- `seedHigh = Float(seed >> 16)` / `seedLow = Float(seed & 0xffff)` are each in [0, 65535], well
  inside Float32's 24-bit exact-integer range, so no mantissa rounding occurs regardless of the
  original UInt32's magnitude — the collision described in the issue (`Float(seed) ==
  Float(seed+100)` near 2^32) cannot recur for either half.
- The GLSL kernel keeps `seedHigh`/`seedLow` as separate phase offsets rather than recombining them
  into one large value before hashing (recombining near 2^32 would just reintroduce the original
  bug) — confirmed by reading `grainHash`/`grainValueNoise`/`effectsGrain` source in the diff.
- Per-octave decorrelation (`seedLow + 1.0/7.0/19.0/43.0`) only perturbs the low half, leaving the
  high half fixed per seed — consistent with the existing octave-blending design and doesn't
  reintroduce coupling.
- `cacheVersion` bumped 13 → 14, correctly invalidating any render cache entries keyed on the old
  single-Float seed encoding.
- Manually traced the new regression seed pair (`0xDEADBEEF`, `0xDEADBEEF + 100`): low 16 bits go
  48879 → 48979, no carry into the high half, so this specifically exercises a low-bits-only
  collision as described in scope.

**Scope**
- No changes to Amount/Size/Roughness mapping or noise shaping beyond the seed-encoding plumbing
  required — matches "Out of scope."
- No public API/schema changes; `applyGrain`'s signature and default seed are unchanged.

**Checks run (this session)**
- `swift build` — clean.
- `swift test` — 463 passed, 25 expected skips, 0 failures (including the new
  `EffectsPipelineTests` low-bit-seed-delta assertion and all other grain/effects tests).
- `dg validate` — OK (pre-existing runner-model warning and LUMO-040 low-context warning only,
  unrelated to this issue).

No follow-up child tickets needed.
