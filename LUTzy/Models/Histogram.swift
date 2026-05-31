import Foundation
import CoreGraphics

/// Per-channel tonal distribution of an image, in 256 bins (one per 8-bit
/// level). Computed from a downscaled RGBA8 render — see
/// `ImageProcessor.histogram(of:)`.
struct HistogramData: Equatable {

    /// Channels a histogram view can draw.
    enum Channel: CaseIterable {
        case red, green, blue, luma
    }

    let red: [Int]
    let green: [Int]
    let blue: [Int]
    /// Rec. 709 luminance (0.2126R + 0.7152G + 0.0722B).
    let luma: [Int]

    var binCount: Int { red.count }

    func bins(for channel: Channel) -> [Int] {
        switch channel {
        case .red:   return red
        case .green: return green
        case .blue:  return blue
        case .luma:  return luma
        }
    }

    /// Display ceiling used to scale bar heights. The pure-black (0) and
    /// pure-white (255) bins are excluded so a single clipping spike doesn't
    /// flatten the rest of the curve into the floor. Falls back to the absolute
    /// max if the interior is empty.
    private static func displayMax(_ channels: [[Int]]) -> Int {
        var interior = 0
        var absolute = 0
        for bins in channels {
            guard bins.count > 2 else { continue }
            for (i, v) in bins.enumerated() {
                absolute = max(absolute, v)
                if i > 0 && i < bins.count - 1 { interior = max(interior, v) }
            }
        }
        return interior > 0 ? interior : absolute
    }

    /// Bars normalized to 0...1 for drawing, scaled by the appropriate ceiling.
    func normalized(_ channel: Channel) -> [CGFloat] {
        let ceiling = channel == .luma ? HistogramData.displayMax([luma])
                                        : HistogramData.displayMax([red, green, blue])
        guard ceiling > 0 else { return Array(repeating: 0, count: binCount) }
        let denom = CGFloat(ceiling)
        return bins(for: channel).map { min(1, CGFloat($0) / denom) }
    }
}
