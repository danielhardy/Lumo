import Foundation

/// The deterministic policy used by the one-click Auto action.
///
/// Auto is intentionally a baseline, not an image-quality oracle. It uses only the luma and
/// per-channel histograms produced by `RenderEngine.histogram`; it does not inspect subjects,
/// faces, skies, camera profiles, or local regions. The version is part of the policy so a future
/// heuristic can be changed deliberately rather than silently changing the meaning of an existing
/// action during a session.
struct AutoAdjustmentSettings: Sendable, Equatable {
    static let currentVersion = 1
    static let `default` = AutoAdjustmentSettings()

    let version: Int
    let targetMedian: Double
    let targetLowPercentile: Double
    let targetHighPercentile: Double
    let histogramMaxDimension: Int

    init(
        version: Int = AutoAdjustmentSettings.currentVersion,
        targetMedian: Double = 0.48,
        targetLowPercentile: Double = 0.08,
        targetHighPercentile: Double = 0.92,
        histogramMaxDimension: Int = 512
    ) {
        self.version = max(1, min(version, AutoAdjustmentSettings.currentVersion))
        self.targetMedian = Self.finiteClamp(targetMedian, to: 0.05...0.95, fallback: 0.48)
        self.targetLowPercentile = Self.finiteClamp(targetLowPercentile, to: 0...0.5, fallback: 0.08)
        self.targetHighPercentile = Self.finiteClamp(targetHighPercentile, to: 0.5...1, fallback: 0.92)
        self.histogramMaxDimension = max(64, min(histogramMaxDimension, 2048))
    }

    private static func finiteClamp(
        _ value: Double, to range: ClosedRange<Double>, fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// The statistics Auto records from a histogram before choosing any edit values.
///
/// Keeping these values as a small `Sendable` value makes the policy inspectable in tests and in
/// future diagnostics without moving image objects out of `RenderEngine`.
struct AutoImageStatistics: Sendable, Equatable {
    let pixelCount: Int
    let meanLuma: Double
    let medianLuma: Double
    let lowPercentileLuma: Double
    let highPercentileLuma: Double
    let redMean: Double
    let greenMean: Double
    let blueMean: Double
    let lowClipFraction: Double
    let highClipFraction: Double

    var channelMeanSpread: Double {
        max(redMean, max(greenMean, blueMean)) - min(redMean, min(greenMean, blueMean))
    }

    /// Build statistics from the 256-bin histogram contract. Empty or malformed tallies are not
    /// actionable and return nil so the caller can show a terminal failure instead of applying a
    /// guessed edit.
    init?(histogram: HistogramData, settings: AutoAdjustmentSettings = .default) {
        guard histogram.red.count == 256, histogram.green.count == 256,
              histogram.blue.count == 256, histogram.luma.count == 256 else { return nil }
        let count = histogram.luma.reduce(0, +)
        guard count > 0,
              histogram.red.allSatisfy({ $0 >= 0 }),
              histogram.green.allSatisfy({ $0 >= 0 }),
              histogram.blue.allSatisfy({ $0 >= 0 }),
              histogram.luma.allSatisfy({ $0 >= 0 }) else { return nil }

        pixelCount = count
        meanLuma = Self.weightedMean(histogram.luma, count: count)
        medianLuma = Self.percentile(histogram.luma, fraction: 0.5, count: count)
        lowPercentileLuma = Self.percentile(
            histogram.luma, fraction: settings.targetLowPercentile, count: count
        )
        highPercentileLuma = Self.percentile(
            histogram.luma, fraction: settings.targetHighPercentile, count: count
        )
        redMean = Self.weightedMean(histogram.red, count: count)
        greenMean = Self.weightedMean(histogram.green, count: count)
        blueMean = Self.weightedMean(histogram.blue, count: count)
        lowClipFraction = Double(histogram.luma[0]) / Double(count)
        highClipFraction = Double(histogram.luma[255]) / Double(count)
    }

    private static func weightedMean(_ bins: [Int], count: Int) -> Double {
        let total = bins.enumerated().reduce(0.0) { partial, element in
            partial + Double(element.offset) * Double(element.element)
        }
        return min(max(total / Double(count) / 255, 0), 1)
    }

    private static func percentile(_ bins: [Int], fraction: Double, count: Int) -> Double {
        let target = max(0, min(count - 1, Int((Double(count - 1) * fraction).rounded(.down))))
        var cumulative = 0
        for (index, bin) in bins.enumerated() {
            cumulative += bin
            if cumulative > target { return Double(index) / 255 }
        }
        return 1
    }
}

/// The result of the versioned Auto policy.
struct AutoAdjustmentResult: Sendable, Equatable {
    let statistics: AutoImageStatistics
    let light: LightAdjustments
    let color: ColorAdjustments
}

enum AutoAdjustmentAnalyzer {
    /// Analyze a histogram and return a conservative global baseline.
    ///
    /// Exposure targets the median and is capped at ±1.25 EV. Contrast responds to the central
    /// spread, while Highlights/Shadows and Whites/Blacks respond to the percentile tails and
    /// clipping bins. The controls intentionally overlap slightly: every output is clamped to a
    /// narrower photographic envelope than the underlying model range, so a single outlier cannot
    /// request an extreme renderer operation. Color uses only global Vibrance/Saturation. The
    /// channel-mean spread is used as a color-bias guardrail; true white-balance correction is not
    /// attempted because the current global Color model has no channel-temperature control.
    static func analyze(
        histogram: HistogramData,
        settings: AutoAdjustmentSettings = .default
    ) -> AutoAdjustmentResult? {
        guard let statistics = AutoImageStatistics(histogram: histogram, settings: settings) else {
            return nil
        }

        let median = max(statistics.medianLuma, 0.03)
        let exposure = bounded(
            log2(settings.targetMedian / median), range: -1.25...1.25
        )

        // A low percentile spread is usually a veiled/low-contrast input. A wide spread needs a
        // small negative move because pushing it farther would turn its tails into clipping.
        let spread = statistics.highPercentileLuma - statistics.lowPercentileLuma
        let contrast = bounded((0.76 - spread) * 120, range: -30...42)

        let highlights = bounded(
            -((statistics.highPercentileLuma - 0.76) * 135
                + statistics.highClipFraction * 180), range: -38...8
        )
        let shadows = bounded(
            (0.24 - statistics.lowPercentileLuma) * 135
                + statistics.lowClipFraction * 180, range: -8...38
        )
        let whites = bounded((0.92 - statistics.highPercentileLuma) * 90, range: -22...18)
        let blacks = bounded((0.08 - statistics.lowPercentileLuma) * 90, range: -18...22)

        let saturation: Double
        if statistics.highClipFraction > 0.01 || statistics.channelMeanSpread > 0.28 {
            saturation = bounded(
                -(statistics.highClipFraction * 260 + max(0, statistics.channelMeanSpread - 0.28) * 45),
                range: -22...0
            )
        } else {
            saturation = 0
        }
        let vibrance = statistics.channelMeanSpread < 0.12 && spread < 0.72
            ? bounded((0.72 - spread) * 26, range: 0...18)
            : 0

        let light = LightAdjustments(
            exposure: exposure,
            contrast: contrast,
            highlights: highlights,
            shadows: shadows,
            whites: whites,
            blacks: blacks
        )
        let color = ColorAdjustments(vibrance: vibrance, saturation: saturation)
        return AutoAdjustmentResult(statistics: statistics, light: light, color: color)
    }

    private static func bounded(_ value: Double, range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
