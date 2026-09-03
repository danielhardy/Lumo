# Auto adjustment

Lumo's v1 Auto action is a deterministic baseline for global Light and Color controls. It is not
an image-quality oracle and makes no semantic or camera-profile claims.

## Heuristic

Auto requests a 512-pixel-capped RGBA8 histogram from the same source/render engine used by the
preview. It records the luma mean, median, 8th and 92nd percentiles, black/white clipping-bin
fractions, and per-channel means. The current policy (version 1) then:

- moves the luma median toward 0.48 with at most ±1.25 EV;
- uses the 8th–92nd percentile spread for restrained Contrast;
- uses the percentile tails and exact 0/255 bins for Highlights, Shadows, Whites, and Blacks;
- reduces global Saturation for strong channel imbalance or white clipping, and adds restrained
  Vibrance only to low-contrast, low-spread inputs.

All values are finite, clamped, and narrower than the corresponding renderer range. Auto writes only
`EditDocument.light` and the global `EditDocument.color.vibrance`/`saturation` values. Existing RAW
develop settings, legacy adjustment nodes, Looks, Effects, crop, and the Color mixer/grading state
are preserved. The action explicitly replaces the current global Light and global Color baseline;
one undo restores the previous document.

The channel-mean spread is a guardrail, not white-balance correction. The current global Color model
does not have a temperature/tint field, so a color cast may remain. RAW profiling, local/semantic
adjustments, Looks/LUTs, and subjective “good” exposure are intentionally out of scope.

## Quality rubric and fixtures

The deterministic tests use generated histogram fixtures representing neutral, clipped, low-key,
high-contrast, and color-biased inputs. They assert policy stability, finite values, renderer-range
bounds, and expected direction of the conservative response; they do not assert that an image looks
subjectively good. Real-world RAW files under `realworldtest/` remain local, non-redistributable
manual fixtures and are not required for unit-test reproducibility.
