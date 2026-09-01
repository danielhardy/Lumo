# Effects validation matrix

The Effects ship gate uses generated fixtures in `EffectsPipelineTests` for deterministic CI
coverage, plus real RAW captures through the Instruments recipe in `docs/INSTRUMENTS.md`. The
generated cases represent the failure modes that can be checked without committing large binaries:

| Case | Representative content | Gate |
| --- | --- | --- |
| Hazy | Low-contrast warm field with a broad luminance ramp | Dehaze changes tone and colour beyond local detail; no extent change |
| High detail | Fine checkerboard over a broad ramp | Texture favours detail; Clarity remains a distinct broader operation |
| Portrait | Skin-like warm midtone field with highlight and shadow patches | Moderate effects preserve alpha/extent and avoid channel clipping |
| High ISO | Deterministic fine-grain field over a neutral image | Grain is repeatable, size/roughness are independent, and preview/full scale remain comparable |

The quality rubric is perceptual rather than pixel-matching: a control must be predictable and useful,
retain geometry and alpha, avoid objectionable halos/clipping at moderate values, and remain distinct
from the other Effects controls. Real-photo review should compare the four cases against Apple Photos,
Lightroom, and the camera JPEG when those references are available.

The interactive gate is measured separately from the unit tests. Run the opt-in Effects benchmark on
the reference Apple Silicon Mac with `LUMO_BENCH=1 swift test --filter PreviewCostBenchmark`, then
capture p50/p95 input-to-present signposts for 24 MP and 40–60 MP RAW files. XCTest proves the binding
uses the interactive/coalesced path; Instruments supplies the hardware-specific timing result.
